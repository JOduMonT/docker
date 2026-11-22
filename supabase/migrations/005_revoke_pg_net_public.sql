-- 005: close pg_net to PUBLIC. Apply as supabase_admin (owner of schema net):
--   python migrations/apply.py --as supabase_admin migrations/005_revoke_pg_net_public.sql
--
-- Why: this database still had pg_net's open defaults (schema USAGE, EXECUTE
-- on every function and full rights on the queue tables for PUBLIC), so every
-- login role, including pipeline_agent, dashboard_ro and ops_app, could send
-- HTTP requests from inside Postgres to services on the Docker network
-- (e.g. supabase-meta runs SQL as postgres, unauthenticated). This sets the
-- state Supabase's own grant_pg_net_access event trigger intends, which never
-- ran here: http_get/http_post SECURITY DEFINER with a pinned search_path,
-- revoked from PUBLIC, granted to Supabase's own roles only. Idempotent; a
-- database without pg_net (e.g. the test database) is left alone.
-- A PUBLIC grant reaches every role, whatever is revoked from a named role,
-- so an `ALTER EXTENSION pg_net UPDATE` or a Supabase upgrade that re-grants
-- PUBLIC reopens the path. After every Supabase or pg_net upgrade: re-run this
-- file and the check query at the end (or tools test_roles_cannot_reach_pg_net).
-- See migrations/README.md.

do $$
declare r text;
begin
  if to_regnamespace('net') is null then
    raise notice 'no schema net here: nothing to do';
    return;
  end if;

  execute 'revoke all on schema net from public';
  execute 'revoke all on all functions in schema net from public';
  execute 'revoke all on all tables in schema net from public';
  execute 'revoke all on all sequences in schema net from public';

  execute 'alter function net.http_get(text, jsonb, jsonb, integer) security definer';
  execute 'alter function net.http_post(text, jsonb, jsonb, jsonb, integer) security definer';
  execute 'alter function net.http_get(text, jsonb, jsonb, integer) set search_path = net';
  execute 'alter function net.http_post(text, jsonb, jsonb, jsonb, integer) set search_path = net';

  -- Exactly what Supabase grants (webhooks run as supabase_functions_admin).
  execute 'grant usage on schema net to supabase_functions_admin, postgres, anon, authenticated, service_role';
  execute 'grant execute on function net.http_get(text, jsonb, jsonb, integer), '
          'net.http_post(text, jsonb, jsonb, jsonb, integer) '
          'to supabase_functions_admin, postgres, anon, authenticated, service_role';

  -- Belt and braces only: these revokes drop direct grants to our roles; they do
  -- NOT block a future grant to PUBLIC (see the header).
  foreach r in array array['pipeline_agent', 'dashboard_ro', 'ops_app'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on schema net from %I', r);
      execute format('revoke all on all functions in schema net from %I', r);
      execute format('revoke all on all tables in schema net from %I', r);
    end if;
  end loop;
end $$;

-- Check (expect all false):
--   select r, has_schema_privilege(r, 'net', 'USAGE'),
--          has_function_privilege(r, 'net.http_post(text,jsonb,jsonb,jsonb,integer)', 'EXECUTE')
--   from unnest(array['pipeline_agent','dashboard_ro','ops_app']) r;
