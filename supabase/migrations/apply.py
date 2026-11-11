"""Apply one migration file to the local Supabase database, inside one transaction.

Usage (from the supabase folder):  python migrations/apply.py [--as supabase_admin] [--db <database>] migrations/003_pipeline_content.sql

Runs `psql` inside the supabase-db container as postgres, with ON_ERROR_STOP
and --single-transaction, so a failing file changes nothing. Secrets the file
needs as psql variables (:'name') are read from supabase/.env and sent on
stdin, never on a command line, never printed:
  pipeline_agent_password <- PIPELINE_AGENT_PASSWORD
  dashboard_ro_password   <- DASHBOARD_RO_PASSWORD
"""
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENV = HERE.parent / ".env"
VARS = {"pipeline_agent_password": "PIPELINE_AGENT_PASSWORD",
        "dashboard_ro_password": "DASHBOARD_RO_PASSWORD"}


def env_value(key: str) -> str:
    for line in ENV.read_text(encoding="utf-8").splitlines():
        m = re.match(rf"^{key}=(.*)$", line.strip())
        if m:
            return m.group(1).strip().strip('"').strip("'")
    raise SystemExit(f"{key} is missing from {ENV}")


def main() -> int:
    args = sys.argv[1:]
    user = "postgres"
    if args[:1] == ["--as"]:
        user, args = args[1], args[2:]
        if user not in ("postgres", "supabase_admin"):
            raise SystemExit("--as must be postgres or supabase_admin")
    db = "postgres"
    if args[:1] == ["--db"]:
        db, args = args[1], args[2:]
        if not db.replace("_", "").isalnum():
            raise SystemExit("--db must be a plain database name")
    if len(args) != 1:
        raise SystemExit(__doc__)
    sql = Path(args[0]).read_text(encoding="utf-8")
    pre = []
    for var, key in VARS.items():
        if re.search(rf":'{var}'", sql):
            val = env_value(key)
            if not re.fullmatch(r"[A-Za-z0-9_-]{24,}", val):
                raise SystemExit(f"{key} must be 24+ chars of [A-Za-z0-9_-]")
            pre.append(f"\\set {var} '{val}'")
    script = "\n".join(pre + [sql]) + "\n"
    r = subprocess.run(
        ["docker", "exec", "-i", "supabase-db", "psql", "-U", user, "-d", db,
         "-v", "ON_ERROR_STOP=1", "--single-transaction", "-q", "-f", "-"],
        input=script.encode("utf-8"), capture_output=True)
    out = (r.stdout + r.stderr).decode("utf-8", "replace")
    for v in VARS.values():  # belt and braces: never echo a secret
        try:
            out = out.replace(env_value(v), "<redacted>")
        except SystemExit:
            pass
    print(out.strip() or "(no output)")
    print(f"{Path(args[0]).name} as {user} on {db}: {'applied' if r.returncode == 0 else 'FAILED, rolled back'}")
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
