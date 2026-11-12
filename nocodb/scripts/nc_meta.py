"""NocoDB metadata helper for the read-only Supabase base (no source settings are changed).

  python scripts/nc_meta.py add-source SCHEMA          # add a read-only source (nocodb_ro, schema+data read-only)
  python scripts/nc_meta.py sync SOURCE_ALIAS          # meta-diff sync of one source (picks up new DB types)
  python scripts/nc_meta.py fields SCHEMA.TABLE COL..  # print NocoDB's field type (uidt) and options
  python scripts/nc_meta.py kanban-test SCHEMA.TABLE COL  # create a Kanban view grouped by COL, report, delete it

Reads the admin login from ../.env; prints no secret.
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
B = "http://127.0.0.1:8091"
BASE_TITLE = "SupaBase"


def call(method, path, body=None, tok=None):
    req = urllib.request.Request(B + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **({"xc-auth": tok} if tok else {})})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")[:400]


def login():
    st, r = call("POST", "/api/v1/auth/user/signin",
                 {"email": ENV["NC_ADMIN_EMAIL"].strip(), "password": ENV["NC_ADMIN_PASSWORD"].strip()})
    if st != 200:
        raise SystemExit(f"signin failed: {st}")
    return r["token"]


def base(tok):
    return next(b for b in call("GET", "/api/v2/meta/bases", tok=tok)[1]["list"] if b["title"] == BASE_TITLE)


def sources(tok, bid):
    return {s.get("alias"): s for s in call("GET", f"/api/v2/meta/bases/{bid}/sources", tok=tok)[1]["list"]}


def table(tok, bid, schema, name):
    srcs = sources(tok, bid)
    sid = srcs[schema]["id"]
    for t in call("GET", f"/api/v2/meta/bases/{bid}/tables", tok=tok)[1]["list"]:
        if t["table_name"] == name and t["source_id"] == sid:
            return call("GET", f"/api/v2/meta/tables/{t['id']}", tok=tok)[1]
    raise SystemExit(f"{schema}.{name} not found in NocoDB")


def main(a):
    tok = login()
    bid = base(tok)["id"]
    if a[0] == "add-source":   # read-only source for one schema, same flags as pipeline/content/ops
        schema = a[1]
        if schema in sources(tok, bid):
            print(f"source {schema}: exists"); return 0
        conn = {"host": "host.docker.internal", "port": 54322, "user": "nocodb_ro.openbot",
                "password": ENV["NOCODB_RO_PASSWORD"].strip(), "database": "postgres", "ssl": False}
        for _ in range(60):
            st, r = call("POST", f"/api/v2/meta/bases/{bid}/sources", {
                "alias": schema, "type": "pg", "is_schema_readonly": True, "is_data_readonly": True,
                "inflection_column": "none", "inflection_table": "none",
                "config": {"client": "pg", "connection": conn, "searchPath": [schema], "pool": {"min": 0, "max": 1}}}, tok)
            if st in (200, 201):
                break
            if "in progress" in str(r):
                time.sleep(3); continue
            print(f"source {schema}: {st} {r}"); return 1
        for _ in range(40):
            s = sources(tok, bid).get(schema)
            if s:
                print(f"source {schema}: created, schema_readonly={s.get('is_schema_readonly')} data_readonly={s.get('is_data_readonly')}")
                return 0
            time.sleep(3)
        print(f"source {schema}: not visible after create"); return 1
    if a[0] == "sync":
        sid = sources(tok, bid)[a[1]]["id"]
        st, r = call("POST", f"/api/v2/meta/bases/{bid}/meta-diff/{sid}", {}, tok)
        print("sync", a[1], st, r if st >= 300 else "")
        time.sleep(8)
        return 0 if st < 300 else 1
    schema, name = a[1].split(".")
    t = table(tok, bid, schema, name)
    cols = {c["column_name"]: c for c in t["columns"]}
    if a[0] == "fields":
        for c in a[2:]:
            col = cols[c]
            opts = [o["title"] for o in (col.get("colOptions") or {}).get("options", [])]
            print(f"{a[1]}.{c}: {col['uidt']} {opts}")
        return 0
    if a[0] == "kanban-test":
        col = cols[a[2]]
        st, v = call("POST", f"/api/v2/meta/tables/{t['id']}/kanbans",
                     {"title": f"zz-kanban-test-{a[2]}", "fk_grp_col_id": col["id"]}, tok)
        print("create kanban:", st, v if st >= 300 else v.get("id"))
        if st < 300:
            vid = v.get("id") or v.get("fk_view_id")
            st2, _ = call("DELETE", f"/api/v2/meta/views/{vid}", tok=tok)
            print("deleted test view:", st2)
        return 0 if st < 300 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
