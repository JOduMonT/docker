"""Apply one migration file to a Supabase database, inside one transaction.

Usage (from the supabase folder):
  python migrations/apply.py [--target cloud|local] [--as supabase_admin] [--db <database>] [--force-password] migrations/003_pipeline_content.sql

--target cloud (default): the hosted project JDmnT (ref gwkolzliiqxkxdchgetp),
  as postgres through the session pooler, sslmode=require. The postgres
  password is read from the OpenBot key file JDMNT_DB_URL (path in env
  JDMNT_DB_URL_FILE, else the Goibniu vault path); role passwords and the
  pooler host come from Shared/_secrets/jdmnt.env. Local passwords never go to
  the cloud. Each applied file is recorded in supabase_migrations.schema_migrations.
--target local: the local stack (supabase-db container), read-only since the
  2026-11-16 move; kept for rollback and tests (--db pipeline_test).

Runs `psql` inside the supabase-db container with ON_ERROR_STOP and
--single-transaction, so a failing file changes nothing. Secrets the file
needs as psql variables (:'name') are sent on stdin or through the process
environment, never on a command line, never printed.
"""
import os
import re
import subprocess
import sys
import urllib.parse as up
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENV = HERE.parent / ".env"
CLOUD_ENV = HERE.parents[2] / "_secrets" / "jdmnt.env"   # Shared/_secrets/jdmnt.env
CLOUD_KEY = os.environ.get("JDMNT_DB_URL_FILE") or str(
    Path.home() / "AppData/Roaming/OpenBot/agent-api-keys/.vault/agent-1f4c1f0f-3fa6-4565-89ca-1ab45893f9e6/JDMNT_DB_URL")
VARS = {"pipeline_agent_password": "PIPELINE_AGENT_PASSWORD",
        "dashboard_ro_password": "DASHBOARD_RO_PASSWORD",
        "nocodb_ro_password": "NOCODB_RO_PASSWORD"}
ROLES = {"pipeline_agent_password": "pipeline_agent", "dashboard_ro_password": "dashboard_ro",
         "nocodb_ro_password": "nocodb_ro"}
# Local only: secrets that live in another stack's .env (kept in one place only).
ENV_FILES = {"NOCODB_RO_PASSWORD": HERE.parent.parent / "nocodb" / ".env"}
TARGET = "cloud"


def _read(path: Path, key: str) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(rf"^{key}=(.*)$", line.strip())
        if m:
            return m.group(1).strip().strip('"').strip("'")
    raise SystemExit(f"{key} is missing from {path}")


def env_value(key: str) -> str:
    if TARGET == "cloud":
        return _read(CLOUD_ENV, key)
    return _read(ENV_FILES.get(key, ENV), key)


def cloud_postgres_password() -> str:
    url = Path(CLOUD_KEY).read_text(encoding="utf-8").strip()
    if "://" not in url:                                   # a bare password is accepted too
        return url
    cred = url.split("://", 1)[1].rsplit("@", 1)[0]       # password may hold '@'
    return up.unquote(cred.split(":", 1)[1])


def login_works(role: str, password: str) -> bool:
    """True when the role already logs in through the pooler with this password."""
    try:
        import psycopg
    except ImportError:
        return False
    if TARGET == "cloud":
        kw = dict(host=env_value("DB_HOST"), port=int(env_value("POSTGRES_PORT")), sslmode="require")
    else:
        kw = dict(host="127.0.0.1", port=int(env_value("POSTGRES_PORT")))
    try:
        psycopg.connect(dbname="postgres", user=f"{role}.{env_value('POOLER_TENANT_ID')}",
                        password=password, connect_timeout=8, **kw).close()
        return True
    except Exception:  # noqa: BLE001 - any failure means "set it"
        return False


def main() -> int:
    global TARGET
    args = sys.argv[1:]
    force_password = "--force-password" in args
    args = [a for a in args if a != "--force-password"]
    if args[:1] == ["--target"]:
        TARGET, args = args[1], args[2:]
        if TARGET not in ("cloud", "local"):
            raise SystemExit("--target must be cloud or local")
    user = "postgres"
    if args[:1] == ["--as"]:
        user, args = args[1], args[2:]
        if user not in ("postgres", "supabase_admin"):
            raise SystemExit("--as must be postgres or supabase_admin")
        if TARGET == "cloud" and user != "postgres":
            raise SystemExit("on cloud only postgres exists for us; run without --as")
    db = "postgres"
    if args[:1] == ["--db"]:
        db, args = args[1], args[2:]
        if not db.replace("_", "").isalnum():
            raise SystemExit("--db must be a plain database name")
        if TARGET == "cloud" and db != "postgres":
            raise SystemExit("--db is local only (tests never touch the cloud)")
    if len(args) != 1:
        raise SystemExit(__doc__)
    path = Path(args[0])
    sql = path.read_text(encoding="utf-8")
    pre = []
    secrets = []
    for var, key in VARS.items():
        if re.search(rf":'{var}'", sql):
            val = env_value(key)
            secrets.append(val)
            if not re.fullmatch(r"[A-Za-z0-9_-]{24,}", val):
                raise SystemExit(f"{key} must be 24+ chars of [A-Za-z0-9_-]")
            pre.append(f"\\set {var} '{val}'")
            # only (re)set a password that does not already work (see 004)
            pre.append(f"\\set set_{var} {'true' if force_password or not login_works(ROLES[var], val) else 'false'}")
    post = []
    env = dict(os.environ)
    if TARGET == "cloud":
        name = path.name.removesuffix(".sql")
        version = "20261116" + name.split("_", 1)[0].rjust(6, "0")
        post = ["create schema if not exists supabase_migrations;",
                "create table if not exists supabase_migrations.schema_migrations "
                "(version text primary key, statements text[], name text);",
                f"insert into supabase_migrations.schema_migrations (version, name) "
                f"values ('{version}', '{name}') on conflict (version) do update set name = excluded.name;"]
        pw = cloud_postgres_password()
        secrets.append(pw)
        env.update(PGHOST=env_value("DB_HOST"), PGPORT=env_value("POSTGRES_PORT"),
                   PGUSER=f"postgres.{env_value('POOLER_TENANT_ID')}", PGPASSWORD=pw,
                   PGDATABASE="postgres", PGSSLMODE="require")
        cmd = ["docker", "exec", "-i"] + sum((["-e", k] for k in
               ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE", "PGSSLMODE")), []) + \
              ["supabase-db", "psql", "-v", "ON_ERROR_STOP=1", "--single-transaction", "-q", "-f", "-"]
    else:
        cmd = ["docker", "exec", "-i", "supabase-db", "psql", "-U", user, "-d", db,
               "-v", "ON_ERROR_STOP=1", "--single-transaction", "-q", "-f", "-"]
    script = "\n".join(pre + [sql] + post) + "\n"
    r = subprocess.run(cmd, input=script.encode("utf-8"), capture_output=True, env=env)
    out = (r.stdout + r.stderr).decode("utf-8", "replace")
    for s in secrets:  # belt and braces: never echo a secret
        out = out.replace(s, "<redacted>")
    print(out.strip() or "(no output)")
    where = "JDmnT" if TARGET == "cloud" else db
    print(f"{path.name} as {user} on {where}: {'applied' if r.returncode == 0 else 'FAILED, rolled back'}")
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
