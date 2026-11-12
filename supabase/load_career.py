#!/usr/bin/env python3
"""Load career-ops file stores into the career schema (one-time migration).

Run from Shared/docker/supabase after 011_career.sql is applied:
    python load_career.py
Reads Shared/career-ops/data/* and upserts into career.* via the session pooler
as postgres. Idempotent: re-running truncates and reloads each table.
Prints one row-count line per table. Fails loudly on parse errors.
"""
import csv, io, json, re, sys
from datetime import datetime
from pathlib import Path

import psycopg

HERE = Path(__file__).resolve().parent              # Shared/docker/supabase
CAREER = HERE.parent.parent / "career-ops" / "data"  # Shared/career-ops/data
ENV = HERE / ".env"


def env(key):
    for line in ENV.read_text(encoding="utf-8").splitlines():
        m = re.match(rf"^{key}=(.*)$", line.strip())
        if m:
            return m.group(1).strip().strip('"').strip("'")
    raise SystemExit(f"{key} missing from {ENV}")


def parse_date(s):
    s = (s or "").strip()
    if not s or s == "-":
        return None
    for fmt in ("%Y-%m-%d", "%d %b %Y", "%b %d %Y"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            pass
    return None


def ts(s):
    s = (s or "").strip()
    if not s:
        return None
    return s.replace("Z", "+00:00")


def tsv_rows(path, skip_comment_header=True):
    """Yield list-of-fields rows from a TSV/CSV, skipping comment/blank preamble."""
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = [l for l in text.splitlines()]
    start = 0
    if skip_comment_header:
        for i, l in enumerate(lines):
            if l.lstrip().startswith("#") or not l.strip():
                start = i + 1
            else:
                break
    rows = []
    for l in lines[start:]:
        if not l.strip():
            continue
        rows.append(next(csv.reader([l], delimiter="\t")))
    return rows


def md_table_rows(path):
    """Yield dict rows from a markdown table (header + separator + data rows)."""
    lines = [l for l in path.read_text(encoding="utf-8", errors="replace").splitlines()]
    rows, header = [], None
    for l in lines:
        if not l.strip().startswith("|"):
            continue
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{2,}:?", c) for c in cells):
            continue  # separator
        if header is None:
            header = [c.lower().replace(" ", "_") for c in cells]
        else:
            rows.append(dict(zip(header, cells)))
    return rows


def main():
    conn = psycopg.connect(host="127.0.0.1", port=int(env("POSTGRES_PORT") or 54322),
                           dbname="postgres", user=f"postgres.{env('POOLER_TENANT_ID')}",
                           password=env("POSTGRES_PASSWORD"), connect_timeout=8)
    conn.autocommit = False

    def load(table, cols, rows):
        conn.execute(f"truncate career.{table} restart identity cascade")
        for r in rows:
            conn.execute(f"insert into career.{table} ({', '.join(cols)}) values ({', '.join(['%s'] * len(cols))})", r)
        n = conn.execute(f"select count(*) from career.{table}").fetchone()[0]
        print(f"career.{table}: {n} rows")

    # connections.csv (LinkedIn export; skip the Notes preamble, find the header)
    raw = CAREER / "Connections.csv"
    text = raw.read_text(encoding="utf-8", errors="replace")
    header_at = next(i for i, l in enumerate(text.splitlines()) if l.startswith("First Name"))
    rdr = csv.DictReader(io.StringIO("\n".join(text.splitlines()[header_at:])))
    load("connections", ["first_name", "last_name", "url", "email", "company", "position", "connected_on"],
         [(r["First Name"], r["Last Name"], r["URL"], r["Email Address"], r["Company"], r["Position"],
           parse_date(r["Connected On"])) for r in rdr])

    # contacts.tsv
    rows = tsv_rows(CAREER / "contacts.tsv")[1:]  # skip header row (after '#' comment)
    load("contacts", ["name", "company", "contact_type", "title", "phone", "email", "linkedin", "tracker_ref", "notes"],
         [tuple(r[i] if i < len(r) else None for i in range(9)) for r in rows])

    # portal-health.tsv
    rows = tsv_rows(CAREER / "portal-health.tsv")[1:]
    load("portal_health", ["checked_at", "company", "status"],
         [(ts(r[0]) if r else None, r[1] if len(r) > 1 else None, r[2] if len(r) > 2 else None) for r in rows])

    # scan-history.tsv
    rows = tsv_rows(CAREER / "scan-history.tsv")[1:]
    load("scan_history", ["url", "first_seen", "portal", "title", "company", "status", "location",
                          "fingerprint", "posted_at", "trust_score", "trust_flags", "normalized_company"],
         [tuple((parse_date(r[i]) if i in (1, 8) else (r[i] if i < len(r) else None)) for i in range(12)) for r in rows])

    # scan-runs.tsv
    rows = tsv_rows(CAREER / "scan-runs.tsv")[1:]
    cols = ["started_at", "status", "companies", "boards", "found", "filtered_title", "filtered_tier",
            "filtered_location", "filtered_posting_age", "filtered_salary", "filtered_content",
            "filtered_cooldown", "dupes", "new_added", "errors", "filtered_blacklist", "filtered_visa",
            "filtered_posted_date", "filtered_country_eligibility"]
    load("scan_runs", cols, [(ts(r[0]) if r else None, r[1] if len(r) > 1 else None) +
                             tuple(int(x) if (x and x.strip().isdigit()) else None for x in (r[2:] if len(r) > 2 else [])) for r in rows])

    # status-log.tsv (no header: ref, at, from, to, action, extra)
    rows = tsv_rows(CAREER / "status-log.tsv", skip_comment_header=False)
    load("status_log", ["ref", "at", "from_status", "to_status", "action", "extra"],
         [tuple((parse_date(r[i]) if i == 1 else (r[i] if i < len(r) else None)) for i in range(6)) for r in rows])

    # salary-observations.tsv (no header: -, at, kind, amount, currency, source, note)
    rows = tsv_rows(CAREER / "salary-observations.tsv", skip_comment_header=False)
    load("salary_observations", ["at", "kind", "amount", "currency", "source", "note"],
         [(parse_date(r[1]), r[2], r[3], r[4], r[5], r[6] if len(r) > 6 else None) for r in rows])

    # pdf-index.tsv
    rows = tsv_rows(CAREER / "pdf-index.tsv")[1:]
    load("pdf_index", ["report", "pdf", "html", "format", "generated_on", "kind"],
         [tuple((parse_date(r[i]) if i == 4 else (r[i] if i < len(r) else None)) for i in range(6)) for r in rows])

    # intake-state.json
    state = json.loads((CAREER / "intake-state.json").read_text(encoding="utf-8"))
    conn.execute("truncate career.intake_state")
    conn.execute("insert into career.intake_state (id, state) values (1, %s)", (json.dumps(state),))
    print(f"career.intake_state: 1 row")

    # applications.md (markdown table)
    app_rows = md_table_rows(CAREER / "applications.md")
    load("applications", ["id", "applied_on", "company", "via", "role", "score", "status", "pdf_ok", "report", "notes"],
         [(int(r.get("#") or 0), parse_date(r.get("date")), r.get("company"), r.get("via"), r.get("role"),
           r.get("score"), r.get("status"), True if "✅" in (r.get("pdf") or "") else (False if "❌" in (r.get("pdf") or "") else None),
           (r.get("report") or "").strip(), r.get("notes")) for r in app_rows if (r.get("#") or "").strip().isdigit()])

    # follow-ups.md: empty table; the real items are bullet lines
    fu_lines = [l.strip() for l in (CAREER / "follow-ups.md").read_text(encoding="utf-8").splitlines()
                if l.strip().startswith("- ")]
    load("follow_ups", ["notes"], [(l[2:],) for l in fu_lines])

    conn.commit()
    conn.close()
    print("career load complete")


if __name__ == "__main__":
    main()
