# Database migrations (local Supabase)

Applied by hand, in order, each in one transaction:

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
