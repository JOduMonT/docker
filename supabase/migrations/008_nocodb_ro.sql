-- 008: nocodb_ro, the read-only role NocoDB uses to show our data (Shared/docker/nocodb).
-- Password: NOCODB_RO_PASSWORD in nocodb/.env, passed by apply.py as a psql
-- variable (stdin, never printed). NocoDB connects through the session pooler as
-- nocodb_ro.<POOLER_TENANT_ID>. Idempotent.
--
-- Reads: pipeline, content, ops (tables and views that exist when this runs).
-- Not reference: the YES Decks cards are paid course material, and NocoDB offers
-- bulk export, API tokens and shared views (Momus review 2026-11-12); add it only
-- if Jon asks. Nothing else: no auth, storage, vault, private, net, extensions,
-- no functions, no writes. Read-only is enforced by grants (SELECT only) and RLS
-- policies (SELECT only); default_transaction_read_only is a second layer.
--
-- Tables added later are NOT exposed automatically (no default privileges): a
-- migration that adds a table NocoDB should show grants it and adds the policy
-- explicitly, so exposure is always a deliberate, reviewed choice.

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'nocodb_ro') then
    create role nocodb_ro login;
  end if;
end $$;

\if :set_nocodb_ro_password
alter role nocodb_ro password :'nocodb_ro_password';
\endif
-- created by postgres (not a superuser): no superuser, createdb, createrole,
-- bypassrls or replication. Pool: NocoDB's per-source pool must stay <= 5.
alter role nocodb_ro noinherit connection limit 5;
alter role nocodb_ro set default_transaction_read_only = on;
alter role nocodb_ro set statement_timeout = '30s';
alter role nocodb_ro set search_path = pipeline, content, ops;

grant usage on schema pipeline, content, ops to nocodb_ro;
grant select on all tables in schema pipeline, content, ops to nocodb_ro;

-- RLS is on for these tables: one SELECT-only policy per table for this role.
do $$
declare t record;
begin
  for t in select n.nspname, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname in ('pipeline', 'content', 'ops') and c.relkind in ('r', 'p')
             and c.relrowsecurity loop
    execute format('drop policy if exists nocodb_ro_read on %I.%I', t.nspname, t.relname);
    execute format('create policy nocodb_ro_read on %I.%I for select to nocodb_ro using (true)',
                   t.nspname, t.relname);
  end loop;
end $$;

-- Functions: PUBLIC's EXECUTE on new functions is a global default, which a
-- per-schema ALTER DEFAULT PRIVILEGES cannot remove (tried: no effect). So every
-- migration that adds a function to pipeline/content/reference/ops must revoke
-- it from PUBLIC itself, as 003 and 006 do. A global
-- `alter default privileges for role postgres revoke execute on functions from public`
-- would enforce it everywhere (all schemas): Jon's call, not done here.

-- Check (expect only pipeline, content, ops and public true; public is empty):
--   select s, has_schema_privilege('nocodb_ro', s, 'USAGE') from unnest(array[
--     'pipeline','content','reference','ops','auth','storage','vault','private','net','public','extensions']) s;
