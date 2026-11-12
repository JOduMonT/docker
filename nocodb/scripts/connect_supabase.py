"""Connect the local Supabase to NocoDB as read-only data sources, then verify.

Creates (once) the base "Supabase (read-only)" with one source per schema
(pipeline, content, ops) through the session pooler host.docker.internal:54322
as nocodb_ro (migration 008). Sources are marked schema- and data-read-only in
NocoDB, and the role itself can only SELECT. Then it lists the tables NocoDB
sees and proves a write fails. Reads secrets from ../.env; prints none.

Usage (from Shared\\docker\\nocodb):  python scripts/connect_supabase.py [--check-only]
"""
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
ENV = dict(re.findall(r"^([A-Z_]+)=(.*)$", (HERE / ".env").read_text(encoding="utf-8"), re.M))
B = "http://127.0.0.1:8091"          # 127.0.0.1: Python resolves "localhost" slowly here
TITLE = "Supabase (read-only)"
SCHEMAS = ("pipeline", "content", "ops")


def call(method, path, body=None, tok=None):
    req = urllib.request.Request(B + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **({"xc-auth": tok} if tok else {})})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")[:400]


def main() -> int:
    tok = call("POST", "/api/v1/auth/user/signin",
               {"email": ENV["NC_ADMIN_EMAIL"].strip(), "password": ENV["NC_ADMIN_PASSWORD"].strip()})[1]["token"]
    bases = call("GET", "/api/v2/meta/bases", tok=tok)[1]["list"]
    base = next((b for b in bases if b["title"] == TITLE), None)
    if base is None:
        if "--check-only" in sys.argv:
            print("no base yet"); return 1
        base = call("POST", "/api/v2/meta/bases", {"title": TITLE}, tok)[1]
    bid = base["id"]
    conn = {"host": "host.docker.internal", "port": 54322, "user": "nocodb_ro.openbot",
            "password": ENV["NOCODB_RO_PASSWORD"].strip(), "database": "postgres", "ssl": False}

    def sources():
        return {s.get("alias"): s for s in call("GET", f"/api/v2/meta/bases/{bid}/sources", tok=tok)[1]["list"]}

    if "--check-only" not in sys.argv:
        for schema in SCHEMAS:
            for _ in range(60):
                if schema in sources():
                    break
                st, r = call("POST", f"/api/v2/meta/bases/{bid}/sources", {
                    "alias": schema, "type": "pg", "is_schema_readonly": True, "is_data_readonly": True,
                    "inflection_column": "none", "inflection_table": "none",
                    "config": {"client": "pg", "connection": conn, "searchPath": [schema], "pool": {"min": 0, "max": 1}}},
                    tok)
                if st in (200, 201):
                    print(f"source {schema}: created")
                    continue
                if "in progress" in str(r):
                    time.sleep(3); continue
                print(f"source {schema}: {st} {r}"); return 1
    srcs = sources()
    print("sources:", {a: (s.get("is_data_readonly"), s.get("is_schema_readonly")) for a, s in srcs.items() if a})
    tables = call("GET", f"/api/v2/meta/bases/{bid}/tables", tok=tok)[1]["list"]
    by_src = {}
    for t in tables:
        alias = next((a for a, s in srcs.items() if s["id"] == t["source_id"]), "?")
        by_src.setdefault(alias, []).append(t["title"])
    for a in SCHEMAS:
        print(f"  {a}: {len(by_src.get(a, []))} tables/views: {', '.join(sorted(by_src.get(a, [])))}")
    posts = next(t for t in tables if t["table_name"] == "posts")
    st, rows = call("GET", f"/api/v2/tables/{posts['id']}/records?limit=5", tok=tok)
    print("read content.posts:", st, len(rows["list"]) if st == 200 else rows)
    first = rows["list"][0]
    st, r = call("PATCH", f"/api/v2/tables/{posts['id']}/records",
                 [{"post_id": first["post_id"], "campaign": first.get("campaign")}], tok)
    print("write content.posts (must fail):", st, str(r)[:160])
    return 0 if st >= 400 else 1


if __name__ == "__main__":
    sys.exit(main())
