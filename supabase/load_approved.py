#!/usr/bin/env python3
"""Load the Jon-approved data-store migrations into Supabase.

Run from Shared/docker/supabase after 012/013/014 are applied:
    python load_approved.py
Reads books-triage-pipeline/reports, ai-training-courses/data, kobo-panel/data
and upserts into books.*, courses.*, kobo.* via the session pooler as postgres.
Idempotent: truncates and reloads each table. Destructive: re-running wipes any rows
added after the load (one-time migration tool). Prints row counts.
"""
import csv, io, json, re
from datetime import datetime
from pathlib import Path

import psycopg

HERE = Path(__file__).resolve().parent                       # Shared/docker/supabase
SHARED = HERE.parent.parent                                   # Shared
BOOKS = SHARED / "books-triage-pipeline" / "reports"
COURSES = SHARED / "ai-training-courses" / "data"
KOBO = SHARED / "kobo-panel" / "data"
ENV = HERE / ".env"


def env(key):
    for line in ENV.read_text(encoding="utf-8").splitlines():
        m = re.match(rf"^{key}=(.*)$", line.strip())
        if m:
            return m.group(1).strip().strip('"').strip("'")
    raise SystemExit(f"{key} missing from {ENV}")


def parse_ts(s):
    s = (s or "").strip()
    if not s:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(s, fmt).isoformat()
        except ValueError:
            pass
    return None


def to_int(x):
    s = str(x).strip() if x is not None else ""
    return int(s) if re.fullmatch(r"-?\d+", s) else None


def to_float(x):
    s = str(x).strip() if x is not None else ""
    try:
        return float(s) if s else None
    except ValueError:
        return None


def to_bool(x):
    s = str(x).strip().lower() if x is not None else ""
    if s in ("true", "1", "yes", "t", "y"):
        return True
    if s in ("false", "0", "no", "f", "n", ""):
        return False
    return None


def jsonl(path):
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.strip():
            yield json.loads(line)


def main():
    conn = psycopg.connect(host="127.0.0.1", port=int(env("POSTGRES_PORT") or 54322),
                           dbname="postgres", user=f"postgres.{env('POOLER_TENANT_ID')}",
                           password=env("POSTGRES_PASSWORD"), connect_timeout=8)
    conn.autocommit = False

    def load(table, cols, rows):
        conn.execute(f"truncate {table} restart identity cascade")
        for r in rows:
            conn.execute(f"insert into {table} ({', '.join(cols)}) values ({', '.join(['%s'] * len(cols))})", r)
        n = conn.execute(f"select count(*) from {table}").fetchone()[0]
        print(f"{table}: {n} rows")

    # --- books.changes (csv + jsonl share columns) ---
    changes = []
    for r in csv.DictReader(io.StringIO((BOOKS / "changes.csv").read_text(encoding="utf-8", errors="replace"))):
        changes.append((parse_ts(r.get("timestamp")), r.get("batch_id"), to_int(r.get("book_id")), r.get("title"),
                        r.get("field"), r.get("before"), r.get("after"), r.get("source")))
    for r in jsonl(BOOKS / "changes.jsonl"):
        changes.append((parse_ts(r.get("timestamp")), r.get("batch_id"), to_int(r.get("book_id")), r.get("title"),
                        r.get("field"), r.get("before"), r.get("after"), r.get("source")))
    load("books.changes", ["changed_at", "batch_id", "book_id", "title", "field", "before", "after", "source"], changes)

    # --- books.research_log ---
    rl = [(parse_ts(r.get("timestamp")), r.get("source"), to_int(r.get("book_id")), r.get("title"), r.get("field"),
           r.get("current"), r.get("proposed"), to_float(r.get("meta_confidence")), r.get("action"))
          for r in jsonl(BOOKS / "research-log.jsonl")]
    load("books.research_log", ["at", "source", "book_id", "title", "field", "current", "proposed", "meta_confidence", "action"], rl)

    # --- books.triage (csv + jsonl; jsonl has no reason) ---
    triage = []
    for r in csv.DictReader(io.StringIO((BOOKS / "triage.csv").read_text(encoding="utf-8", errors="replace"))):
        triage.append((parse_ts(r.get("timestamp")), r.get("filename"), to_int(r.get("book_id")), r.get("decision"),
                       r.get("domain"), r.get("moscow"), to_float(r.get("confidence")), to_bool(r.get("is_new_domain")),
                       r.get("language"), to_int(r.get("pages")), to_int(r.get("words")), r.get("source_hash"),
                       r.get("reason"), to_bool(r.get("wrote_back")), to_int(r.get("workspace_priority"))))
    for r in jsonl(BOOKS / "triage.jsonl"):
        triage.append((parse_ts(r.get("timestamp")), r.get("filename"), to_int(r.get("book_id")), r.get("decision"),
                       r.get("domain"), r.get("moscow"), to_float(r.get("confidence")), to_bool(r.get("is_new_domain")),
                       r.get("language"), to_int(r.get("pages")), to_int(r.get("words")), r.get("source_hash"),
                       None, to_bool(r.get("wrote_back")), to_int(r.get("workspace_priority"))))
    load("books.triage", ["at", "filename", "book_id", "decision", "domain", "moscow", "confidence", "is_new_domain",
                          "language", "pages", "words", "source_hash", "reason", "wrote_back", "workspace_priority"], triage)

    # --- books.taxonomy ---
    tax = json.loads((BOOKS / "taxonomy.json").read_text(encoding="utf-8"))
    load("books.taxonomy", ["slug", "description", "created", "last_seen", "seen_count"],
         [(r.get("slug"), r.get("description"), parse_ts(r.get("created")), parse_ts(r.get("last_seen")),
           to_int(r.get("seen_count"))) for r in tax])

    # --- courses.catalog / notes / references / stages ---
    load("courses.catalog", ["legacy_id", "course", "proposed_by", "days", "format", "description", "stage",
                             "stage_no", "priority", "next_step", "owner", "updated"],
         [(r.get("ID"), r.get("Course"), r.get("ProposedBy"), r.get("Days"), r.get("Format"), r.get("Description"),
           r.get("Stage"), to_int(r.get("StageNo")), r.get("Priority"), r.get("NextStep"), r.get("Owner"), r.get("Updated"))
          for r in csv.DictReader(io.StringIO((COURSES / "courses.csv").read_text(encoding="utf-8", errors="replace")))])
    load("courses.notes", ["course_id", "note", "source"],
         [(r.get("CourseID"), r.get("Note"), r.get("Source"))
          for r in csv.DictReader(io.StringIO((COURSES / "notes.csv").read_text(encoding="utf-8", errors="replace")))])
    load("courses.references", ["course_id", "ref_type", "title", "author", "link", "use_for", "verified"],
         [(r.get("CourseID"), r.get("Type"), r.get("Title"), r.get("Author"), r.get("Link"), r.get("UseFor"), r.get("Verified"))
          for r in csv.DictReader(io.StringIO((COURSES / "references.csv").read_text(encoding="utf-8", errors="replace")))])
    load("courses.stages", ["stage_no", "stage", "meaning"],
         [(to_int(r.get("StageNo")), r.get("Stage"), r.get("Meaning"))
          for r in csv.DictReader(io.StringIO((COURSES / "stages.csv").read_text(encoding="utf-8", errors="replace")))])

    # --- kobo.briefs ---
    brief = json.loads((KOBO / "brief.json").read_text(encoding="utf-8"))
    conn.execute("truncate kobo.briefs restart identity")
    conn.execute("insert into kobo.briefs (brief_date, generated_at, headline, data) values (%s, %s, %s, %s)",
                 (parse_ts(brief.get("date")), parse_ts(brief.get("generated_at")), brief.get("headline"),
                  json.dumps(brief)))
    print("kobo.briefs: 1 row")

    conn.commit()
    conn.close()
    print("approved migrations loaded")


if __name__ == "__main__":
    main()
