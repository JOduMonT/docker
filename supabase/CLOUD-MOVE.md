# Move local Supabase → hosted JDmnT (Jon, 2026-11-16)

## Outcome (2026-11-16, done)
- Momus: approved with 8 must-fixes, all applied — freeze before the copy (`cloud/jdmnt.py freeze-local`, 65 write grants revoked from pipeline_agent/ops_app, inverse in `backups/pre-cloud-20261116/unfreeze-local.json`); `002_ops_app_role.sql` committed (ops_app NOLOGIN on cloud: no client logs in as ops_app); role passwords only from `Shared/_secrets/jdmnt.env` (new, random; ACL user+SYSTEM; Shared is not cloud-synced); nc_meta.py repointed; product-pipeline tests pinned to local, cloud refused under pytest except the read-only live check; counts + hashes + orphan check inside the load transaction with pinned TimeZone/DateStyle/extra_float_digits; exposure check (0 API-role grants); expected schema diffs = policy role order + 027.
- Schema: migrations 001–027 applied to JDmnT (`supabase_migrations.schema_migrations`). Schema diff local vs cloud: only policy role order (10 policies) and 027.
- Data: one transaction, **40 tables, 19,943 rows**, every table's count and md5 equal, 37 FKs with 0 orphans, 17 sequences set; re-verified after commit (`backups/pre-cloud-20261116/verify-after.tsv`). (Plan said 41 tables: miscount; it is 40.)
- Correction to step 6: `load_approved.py` is retired (it truncates), not repointed; NocoDB had no Supabase source configured, so only its scripts were repointed.
- Still to do by Jon: Network Restrictions and SSL enforcement in the JDmnT dashboard (Momus #6); approve turning the local stack off.

Target: Supabase project **JDmnT**, ref `gwkolzliiqxkxdchgetp`, ca-central-1, Postgres 17 (empty at plan time: no app schemas, no migrations).
Source: local stack `Shared\docker\supabase` (`supabase-db`, PG 17.6). Owner: Goibniu. Review: Momus, once.

## Inventory (exact counts, 2026-11-16)
| schema | tables (rows) |
|---|---|
| core | domain_rules 35, domains 1167, offer_types 6, people_agents 16 |
| reference | yes_cards 102, yes_modifiers 100 |
| ops | data_store_debt 73, task_events 11, tasks 8 (+ view stale_tasks) |
| pipeline | evidence 14, launch_channels 12, runs 10, sync_issues 2, tasks 50 (+5 views) |
| content | campaigns 2, engagement 7, engagement_domains 8, engagement_events 8, hooks 4, narratives 1, post_events 28, post_offer_types 8, posts 8, stories 8, story_domains 12, story_offer_types 10, story_use 0 (+4 views) |
| courses | catalog 16, catalog_domains 33, notes 5, references 101, rehearsal_runs 0, stages 6 (+1 view) |
| books | changes 13281, research_log 764, taxonomy 856, triage 3100 (+1 view) |
| research | triage 70, triage_courses 0 (+1 view) |
| kobo | briefs 1 (frozen snapshot) |
41 tables, 19 935 rows, 15 views, 20 enum types. `public` holds nothing. Extensions used: pgcrypto, uuid-ossp, vector (all available on hosted).
Out of scope: `auth`, `storage`, `vault`, `realtime` (unused by us; never touched).

## Order
0. **Backup** (local, read-only): `pg_dump -Fc` of the 9 schemas + `pg_dumpall --roles-only` → `supabase\backups\pre-cloud-20261116\`; record per-table counts to `counts-local.tsv`. Freeze writers for the window (the routines that write: books triage Mon 14:00, raw capture/triage ledger, pipeline sync) — run between routine slots.
1. **Schema by migrations**: replay `migrations/001…026` in numeric order against JDmnT with `apply.py --target cloud` (new flag: connect as `postgres` through the session pooler, `sslmode=require`, instead of `docker exec`). Each file is recorded in `supabase_migrations.schema_migrations` with the same name, so `list_migrations` matches git. Adjustments, each as a new numbered migration, not edits to old files:
   - 005 (pg_net revoke) runs as `postgres`; skip with a note if hosted ownership refuses it, and check with the existing test query.
   - `027_rls_gaps.sql`: enable RLS on `kobo.briefs` and the ops table without it; add read policies for `nocodb_ro`/`dashboard_ro`, write for `pipeline_agent`/`ops_app` where local grants allow.
   - Data API: our 9 schemas stay **out** of the exposed schemas (hosted default exposes only `public`, `graphql_public`); `anon`/`authenticated` get no grant.
2. **Schema check**: `pg_dump --schema-only` of the 9 schemas, local vs cloud, normalised (owner/ACL lines kept). Any diff other than known 027 → stop and fix with a migration.
3. **Data**: truncate the 9 schemas in cloud (removes seed rows from 022/023), then one `pg_dump --data-only` stream from local, loaded in one transaction with `session_replication_role = replica` (deferred FKs from 025 stay valid), then `setval` from the dump. Order is pg_dump's FK order: core → reference → ops → pipeline → content → courses → books → research → kobo.
4. **Counts after each step**: exact `count(*)` per table in cloud = `counts-local.tsv`; plus row hash per table (`md5(string_agg(t::text, '' order by t::text))`) for the 9 schemas. Mismatch → roll back the transaction / truncate and repeat; local is untouched.
5. **Roles**: create `pipeline_agent`, `ops_app`, `dashboard_ro`, `nocodb_ro` in cloud via 004/008 (with new random passwords generated by the script, written only to `Shared\_secrets\jdmnt.env`, never printed). Login is `<role>.gwkolzliiqxkxdchgetp` on the ca-central-1 session pooler.
6. **Repoint writers** (one commit per repo, each read-back tested with a write + delete on a scratch row, then the repo's own tests):
   - `product-pipeline/tools/pipeline_db/db.py` (+ tests' default DSN)
   - `books-triage-pipeline/bin/books_db.py`
   - `ai-training-courses/tools/courses_db.py`
   - `wiki/scripts/triage_ledger.py`
   - `wiki/scripts/data_store_reconcile.py` (guard; `docker exec` → psycopg on cloud)
   - `docker/supabase/load_approved.py`, `docker/supabase/migrations/apply.py` (default target = cloud; `--target local` kept)
   - NocoDB source (`docker/nocodb/scripts/connect_supabase.py`) → cloud as `nocodb_ro`
   - All read the host/port/tenant/password from `Shared\_secrets\jdmnt.env` (`DB_HOST`, `DB_PORT`, `DB_TENANT`, `*_PASSWORD`, `sslmode=require`); the `*_DSN` overrides stay.
   - Text: team-doctrine "Data lives in Supabase", wiki `AGENTS.md`, role files (research-analyst, compose-keeper, channel-scout, brand-strategist, platform-team), agents' AGENTS.md and the yes-decks skill that name the local DB.
7. **Local read-only**: `revoke insert, update, delete, truncate` on the 9 schemas from `pipeline_agent`, `ops_app` (reversible, recorded as `migrations/local/900_read_only.sql`). Stack keeps running. No `docker compose down`, no volume delete — Jon's call.

## Rollback
Before step 6 commits: nothing changed locally; drop the 9 schemas in cloud. After: revert the repoint commits and re-grant local writes (900 has its inverse); cloud rows written meanwhile are copied back by the same dump path.

## Needs before running
- JDmnT database connection string (session pooler URI with the `postgres` password) as OpenBot key `JDMNT_DB_URL` (saved outside the workspace, read from its file at run time, never printed) — requested from Jon 2026-11-16; not on k12 before.
- Role passwords generated in step 5 go to `Shared\_secrets\jdmnt.env` (git-ignored, outside every repo).
