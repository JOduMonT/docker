# Database migrations (Supabase JDmnT, hosted)

Since 2026-11-16 the live database is the hosted project JDmnT (ref
`gwkolzliiqxkxdchgetp`). `apply.py` targets it by default (`--target cloud`:
postgres through the session pooler, role passwords from
`Shared/_secrets/jdmnt.env`, each file recorded in
`supabase_migrations.schema_migrations`). The local stack is a read-only
fallback; `--target local` is for tests (`--db pipeline_test`) and rollback.
Every numbered file 001–027 is applied to JDmnT (see `../CLOUD-MOVE.md`).

```bash
python migrations/apply.py migrations/028_next_change.sql            # JDmnT
python migrations/apply.py --target local --db pipeline_test migrations/028_next_change.sql
```

Historical local procedure (each file in one transaction):

```bash
python migrations/apply.py migrations/001_ops_tasks.sql
python migrations/apply.py migrations/003_pipeline_content.sql
python migrations/apply.py migrations/004_pipeline_roles.sql        # passwords from .env (PIPELINE_AGENT_PASSWORD, DASHBOARD_RO_PASSWORD); set only if the pooler login fails, or always with --force-password
python migrations/apply.py --as supabase_admin migrations/005_revoke_pg_net_public.sql
python migrations/apply.py migrations/006_yes_decks.sql                # schema only; then load the private data:
python ../../product-pipeline/tools/pipeline_db.py load-yes-decks      # from Shared/Data/yes-decks/merged.json (paid content, never in git)
```

`002_ops_app_role.sql.local` is git-ignored (it holds a password). Every file
is idempotent: re-running it is safe. `--db <name>` targets another database
(the tests use `pipeline_test`).

## After every Supabase or pg_net upgrade

A grant to PUBLIC reaches every role. If an upgrade re-grants pg_net to PUBLIC,
the agents' and Appsmith's roles can send HTTP requests from inside Postgres
again (supabase-meta on the Docker network runs SQL as postgres without a
key). So after each upgrade:

```bash
python migrations/apply.py --as supabase_admin migrations/005_revoke_pg_net_public.sql
docker exec supabase-db psql -U supabase_admin -tAc "select r, has_schema_privilege(r,'net','USAGE') from unnest(array['pipeline_agent','dashboard_ro','ops_app']) r"
```

Every line must end in `f`. `update.sh` prints this reminder.

## Enum columns (017-020)

Fixed-list columns are Postgres enums so NocoDB (schema edit off) shows them as Single select and allows Kanban.
Writers send plain strings: literals and untyped parameters work, and each type has an assignment cast from text.
To add a value: write a new migration with `alter type <schema>.<type> add value '<label>';` and apply it
**before** any writer emits the new value (inside a transaction the new label is usable only after commit).
Labels can never be removed or renamed without rebuilding the type (and recreating the views that use it).
Columns that writers fill freely stay text (books.triage.moscow, research.triage.source_type, the language columns).
