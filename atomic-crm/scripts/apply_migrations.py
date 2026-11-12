"""Apply Atomic CRM's Supabase migrations to the shared local Supabase, safely.

Usage (from Shared\\docker\\atomic-crm):
  python scripts/apply_migrations.py --dry-run   # all pending migrations in ONE transaction, then ROLLBACK
  python scripts/apply_migrations.py             # apply pending ones, each in its own transaction

- Reads src/supabase/migrations/*.sql in order (the pinned upstream clone).
- Runs as `postgres` (like the Supabase CLI does), via psql inside supabase-db.
- Records each applied file in supabase_migrations.schema_migrations
  (the table the Supabase CLI uses), so a file is never applied twice.
- Patches upstream SQL that would damage the shared stack (see PATCHES);
  a patch whose text is not found stops the run.
- After the CRM migrations, applies ../supabase/migrations/007_atomic_crm_hardening.sql as supabase_admin
  and re-applies 005 (pg_net closed to PUBLIC) as supabase_admin.
"""
import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent          # Shared/docker/atomic-crm
MIG = HERE / "src" / "supabase" / "migrations"
SUPA = HERE.parent / "supabase"

# file -> [(exact upstream text, replacement, why)]
PATCHES = {
    "20260309112831_fix_security_warnings.sql": [(
        "DROP EXTENSION IF EXISTS pg_net CASCADE;\nCREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;",
        "-- [openbot] skipped: pg_net is already in schema extensions here. Upstream drops it\n"
        "-- with CASCADE (would remove Supabase's webhook functions) and recreates it with\n"
        "-- PUBLIC grants (would undo migration 005).",
        "never drop/recreate the shared pg_net"),
    ],
}

TRACK = """create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (
  version text primary key, statements text[], name text);
"""


def psql(sql: str, user: str = "postgres") -> subprocess.CompletedProcess:
    return subprocess.run(
        ["docker", "exec", "-i", "supabase-db", "psql", "-U", user, "-d", "postgres",
         "-v", "ON_ERROR_STOP=1", "-q", "-X", "-f", "-"],
        input=sql.encode("utf-8"), capture_output=True)


def applied() -> set[str]:
    r = psql("select string_agg(version, ',') from supabase_migrations.schema_migrations;".replace(
        "select", "\\pset tuples_only on\n\\pset format unaligned\nselect", 1))
    out = r.stdout.decode().strip()
    return set(out.split(",")) if r.returncode == 0 and out else set()


def body(f: Path) -> str:
    sql = f.read_text(encoding="utf-8").replace("\r\n", "\n")
    for old, new, why in PATCHES.get(f.name, []):
        if sql.count(old) != 1:
            raise SystemExit(f"{f.name}: patch '{why}' did not match exactly once; stop and review upstream")
        sql = sql.replace(old, new)
    return sql


def record(f: Path) -> str:
    version, _, name = f.stem.partition("_")
    return (f"insert into supabase_migrations.schema_migrations (version, name, statements) "
            f"values ('{version}', '{name}', array['applied by openbot apply_migrations.py']) "
            f"on conflict (version) do nothing;\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    r = psql(TRACK)
    if r.returncode:
        print(r.stderr.decode()); return 1
    done = applied()
    files = sorted(p for p in MIG.glob("*.sql") if p.stem.split("_")[0] not in done)
    print(f"{len(done)} already applied, {len(files)} pending")
    hardening = (SUPA / "migrations" / "007_atomic_crm_hardening.sql").read_text(encoding="utf-8")
    if a.dry_run:
        # CRM part as postgres (owner of its objects), hardening as supabase_admin
        script = "begin;\nset role postgres;\n" \
                 + "".join(f"\\echo {f.name}\n" + body(f) + "\n" + record(f) for f in files) \
                 + "reset role;\n" + hardening + "\nrollback;\n"
        r = psql(script, user="supabase_admin")
        print((r.stdout + r.stderr).decode()[-3000:])
        print("DRY RUN:", "all statements succeeded, rolled back" if r.returncode == 0 else "FAILED, rolled back")
        return r.returncode
    for f in files:
        r = psql("begin;\n" + body(f) + "\n" + record(f) + "commit;\n")
        status = "ok" if r.returncode == 0 else "FAILED (rolled back)"
        print(f"{f.name}: {status}")
        if r.returncode:
            print(r.stderr.decode()[-2000:]); return 1
    r = psql("begin;\n" + hardening + "\ncommit;\n", user="supabase_admin")   # http functions belong to it
    print("007_atomic_crm_hardening.sql:", "ok" if r.returncode == 0 else "FAILED\n" + r.stderr.decode()[-2000:])
    if r.returncode:
        return 1
    r = subprocess.run([sys.executable, "migrations/apply.py", "--as", "supabase_admin",
                        "migrations/005_revoke_pg_net_public.sql"], cwd=SUPA, capture_output=True, text=True)
    print(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else r.stderr[-500:])
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
