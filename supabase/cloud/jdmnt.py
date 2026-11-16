"""Move the local Supabase app data to the hosted project JDmnT (plan: supabase/CLOUD-MOVE.md).

Usage (from Shared/docker/supabase):
  python cloud/jdmnt.py init-secrets     # write Shared/_secrets/jdmnt.env (new random role passwords), once
  python cloud/jdmnt.py freeze-local     # revoke writes from pipeline_agent/ops_app locally; saves the inverse
  python cloud/jdmnt.py unfreeze-local   # rollback only: re-grant exactly what freeze-local revoked
  python cloud/jdmnt.py move             # one cloud transaction: truncate, copy, setval, verify, commit or roll back
  python cloud/jdmnt.py verify           # counts + hashes local vs cloud (read-only on both)
  python cloud/jdmnt.py exposure         # anon/authenticated/service_role privileges on our schemas (expect none)

Secrets are read from files at run time and never printed: the cloud postgres
password from the OpenBot key file JDMNT_DB_URL, the local postgres password
from supabase/.env, role passwords from Shared/_secrets/jdmnt.env.
"""
import json
import os
import re
import secrets
import string
import subprocess
import sys
import urllib.parse as up
from pathlib import Path

import psycopg

HERE = Path(__file__).resolve().parent
SUPA = HERE.parent
SHARED = SUPA.parents[1]
CLOUD_ENV = SHARED / "_secrets" / "jdmnt.env"
CLOUD_KEY = Path(os.environ.get("JDMNT_DB_URL_FILE") or
                 Path.home() / "AppData/Roaming/OpenBot/agent-api-keys/.vault/agent-1f4c1f0f-3fa6-4565-89ca-1ab45893f9e6/JDMNT_DB_URL")
BACKUP = SUPA / "backups" / "pre-cloud-20261116"
SCHEMAS = ["books", "content", "core", "courses", "kobo", "ops", "pipeline", "reference", "research"]
REF = "gwkolzliiqxkxdchgetp"
POOLER = "aws-0-ca-central-1.pooler.supabase.com"
PIN = "set TimeZone='UTC'; set DateStyle='ISO, MDY'; set extra_float_digits=1; set IntervalStyle='postgres'"
FREEZE_ROLES = ("pipeline_agent", "ops_app")


def _read(path: Path, key: str) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(rf"^{key}=(.*)$", line.strip())
        if m:
            return m.group(1).strip().strip('"').strip("'")
    raise SystemExit(f"{key} missing from {path}")


def local():
    return psycopg.connect(host="127.0.0.1", port=int(_read(SUPA / ".env", "POSTGRES_PORT")), dbname="postgres",
                           user=f"postgres.{_read(SUPA / '.env', 'POOLER_TENANT_ID')}",
                           password=_read(SUPA / ".env", "POSTGRES_PASSWORD"), connect_timeout=10)


def cloud():
    url = CLOUD_KEY.read_text(encoding="utf-8").strip()
    if "://" in url:                                       # URI or bare password
        cred = url.split("://", 1)[1].rsplit("@", 1)[0]    # password may hold '@'
        pw = up.unquote(cred.split(":", 1)[1])
    else:
        pw = url
    return psycopg.connect(host=POOLER, port=5432, dbname="postgres", user=f"postgres.{REF}",
                           password=pw, sslmode="require", connect_timeout=15)


def tables(c) -> list[str]:
    return [r[0] for r in c.execute(
        "select format('%%I.%%I', schemaname, tablename) from pg_tables where schemaname = any(%s) order by 1",
        (SCHEMAS,)).fetchall()]


def columns(c, t: str) -> list[str]:
    """Insertable columns (no generated ones), in attribute order."""
    return [r[0] for r in c.execute(
        "select quote_ident(attname) from pg_attribute where attrelid = %s::regclass and attnum > 0 "
        "and not attisdropped and attgenerated = '' order by attnum", (t,)).fetchall()]


def fingerprint(c) -> dict:
    c.execute(PIN)
    out = {}
    for t in tables(c):
        out[t] = list(c.execute(
            f"select count(*), md5(coalesce(string_agg(x::text, E'\\n' order by x::text), '')) from {t} x").fetchone())
    return out


def orphans(c) -> list:
    """Every FK in our schemas: child rows whose non-null key has no parent."""
    bad = []
    fks = c.execute("""
        select conname, conrelid::regclass::text, confrelid::regclass::text,
               (select array_agg(quote_ident(attname) order by k.i) from unnest(conkey) with ordinality k(n, i)
                  join pg_attribute a on a.attrelid = conrelid and a.attnum = k.n),
               (select array_agg(quote_ident(attname) order by k.i) from unnest(confkey) with ordinality k(n, i)
                  join pg_attribute a on a.attrelid = confrelid and a.attnum = k.n)
        from pg_constraint where contype = 'f' and connamespace::regnamespace::text = any(%s)""", (SCHEMAS,)).fetchall()
    for name, child, parent, ccols, pcols in fks:
        notnull = " and ".join(f"c.{x} is not null" for x in ccols)
        match = " and ".join(f"p.{p} = c.{x}" for x, p in zip(ccols, pcols))
        n = c.execute(f"select count(*) from {child} c where {notnull} and not exists "
                      f"(select 1 from {parent} p where {match})").fetchone()[0]
        if n:
            bad.append((name, child, n))
    return bad, len(fks)


def sequences(c) -> list:
    return c.execute("select format('%%I.%%I', schemaname, sequencename), last_value, start_value from pg_sequences "
                     "where schemaname = any(%s) order by 1", (SCHEMAS,)).fetchall()


def cmd_init_secrets():
    if CLOUD_ENV.exists():
        raise SystemExit(f"{CLOUD_ENV} exists; not overwriting")
    CLOUD_ENV.parent.mkdir(parents=True, exist_ok=True)
    abc = string.ascii_letters + string.digits
    pw = lambda: "".join(secrets.choice(abc) for _ in range(40))  # noqa: E731
    CLOUD_ENV.write_text(
        "# JDmnT (hosted Supabase) connection for k12 writers. Never commit, never print.\n"
        f"DB_HOST={POOLER}\nPOSTGRES_PORT=5432\nPOOLER_TENANT_ID={REF}\nDB_SSLMODE=require\n"
        f"PIPELINE_AGENT_PASSWORD={pw()}\nDASHBOARD_RO_PASSWORD={pw()}\nNOCODB_RO_PASSWORD={pw()}\n",
        encoding="utf-8")
    user = os.environ.get("USERNAME", "")
    for p in (CLOUD_ENV.parent, CLOUD_ENV):
        subprocess.run(["icacls", str(p), "/inheritance:r", "/grant:r", f"{user}:F", "/grant:r", "SYSTEM:F"],
                       check=True, capture_output=True)
    print(f"wrote {CLOUD_ENV} (3 role passwords, ACL: {user} + SYSTEM)")


def cmd_freeze_local():
    BACKUP.mkdir(parents=True, exist_ok=True)
    with local() as c:
        grants = c.execute("""select grantee, format('%%I.%%I', table_schema, table_name), privilege_type
            from information_schema.role_table_grants where grantee = any(%s) and table_schema = any(%s)
            and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE') order by 1,2,3""",
                           (list(FREEZE_ROLES), SCHEMAS)).fetchall()
        inv = BACKUP / "unfreeze-local.json"
        if not inv.exists():
            inv.write_text(json.dumps(grants, indent=1), encoding="utf-8")
        for s in SCHEMAS:
            for r in FREEZE_ROLES:
                c.execute(f"revoke insert, update, delete, truncate on all tables in schema {s} from {r}")
        left = c.execute("""select count(*) from information_schema.role_table_grants where grantee = any(%s)
            and table_schema = any(%s) and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')""",
                         (list(FREEZE_ROLES), SCHEMAS)).fetchone()[0]
    print(f"local frozen: revoked {len(grants)} write grants from {', '.join(FREEZE_ROLES)}; left={left}; inverse in {inv}")


def cmd_unfreeze_local():
    grants = json.loads((BACKUP / "unfreeze-local.json").read_text(encoding="utf-8"))
    with local() as c:
        for role, table, priv in grants:
            c.execute(f"grant {priv} on {table} to {role}")
    print(f"local unfrozen: re-granted {len(grants)} write grants")


def cmd_move():
    with local() as lc:
        lc.execute("begin isolation level repeatable read read only")
        src_tables = tables(lc)
        src_fp = fingerprint(lc)
        src_seq = sequences(lc)
        (BACKUP / "counts-local.tsv").write_text(
            "".join(f"{t}\t{n}\t{h}\n" for t, (n, h) in src_fp.items()), encoding="utf-8")
        with cloud() as cc:
            dst_tables = tables(cc)
            if dst_tables != src_tables:
                raise SystemExit(f"table sets differ: only local={set(src_tables)-set(dst_tables)} "
                                 f"only cloud={set(dst_tables)-set(src_tables)}")
            cc.execute("set session_replication_role = replica")
            cc.execute(PIN)
            cc.execute("truncate " + ", ".join(dst_tables))
            for t in src_tables:
                cols = columns(lc, t)
                if cols != columns(cc, t):
                    raise SystemExit(f"{t}: column lists differ")
                cl = ", ".join(cols)
                with lc.cursor().copy(f"copy (select {cl} from {t}) to stdout") as out, \
                        cc.cursor().copy(f"copy {t} ({cl}) from stdin") as inp:
                    for chunk in out:
                        inp.write(chunk)
            for seq, last, start in src_seq:
                cc.execute("select setval(%s, %s, %s)", (seq, last if last is not None else start, last is not None))
            cc.execute("set session_replication_role = origin")
            dst_fp = fingerprint(cc)
            bad, nfk = orphans(cc)
            diff = {t: (src_fp[t], dst_fp.get(t)) for t in src_fp if src_fp[t] != dst_fp.get(t)}
            seq_diff = [s for s in sequences(cc) if s not in src_seq]
            if diff or bad or seq_diff:
                cc.rollback()
                print(json.dumps({"rolled_back": True, "diff": diff, "orphans": bad, "seq_diff": seq_diff}, default=str))
                return 1
            cc.commit()
    rows = sum(n for n, _ in src_fp.values())
    print(f"committed: {len(src_fp)} tables, {rows} rows, hashes equal, {nfk} FKs with 0 orphans, "
          f"{len(src_seq)} sequences set")
    return 0


def cmd_verify():
    with local() as lc, cloud() as cc:
        lc.execute("set transaction read only"); cc.execute("set transaction read only")
        a, b = fingerprint(lc), fingerprint(cc)
    ok = a == b
    for t in sorted(set(a) | set(b)):
        print(f"{t}\t{a.get(t, ['-'])[0]}\t{b.get(t, ['-'])[0]}\t{'=' if a.get(t) == b.get(t) else 'DIFF'}")
    print(f"{'MATCH' if ok else 'MISMATCH'}: {len(a)} local / {len(b)} cloud tables, "
          f"{sum(v[0] for v in a.values())} / {sum(v[0] for v in b.values())} rows")
    return 0 if ok else 1


def cmd_exposure():
    with cloud() as cc:
        rows = cc.execute("""select s, r, has_schema_privilege(r, s, 'USAGE') from unnest(%s::text[]) s,
            unnest(array['anon','authenticated','service_role']) r order by 1, 2""", (SCHEMAS,)).fetchall()
        api = cc.execute("select coalesce(current_setting('pgrst.db_schemas', true), '') ").fetchone()[0]
        cfg = cc.execute("select rolconfig from pg_roles where rolname = 'authenticator'").fetchone()[0]
    leaks = [r for r in rows if r[2]]
    print(f"usage grants to API roles: {len(leaks)} {leaks}")
    print(f"authenticator config: {cfg}  pgrst.db_schemas: {api!r}")
    return 1 if leaks else 0


if __name__ == "__main__":
    cmds = {"init-secrets": cmd_init_secrets, "freeze-local": cmd_freeze_local, "unfreeze-local": cmd_unfreeze_local,
            "move": cmd_move, "verify": cmd_verify, "exposure": cmd_exposure}
    if len(sys.argv) != 2 or sys.argv[1] not in cmds:
        raise SystemExit(__doc__)
    sys.exit(cmds[sys.argv[1]]() or 0)
