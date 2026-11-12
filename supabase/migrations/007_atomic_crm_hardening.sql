-- 007: hardening after Atomic CRM's migrations (Shared/docker/atomic-crm).
-- Applied by atomic-crm/scripts/apply_migrations.py right after the CRM
-- migrations, as supabase_admin (the http extension's functions belong to it, and
-- only the grantor or a superuser can revoke a grant). Idempotent. The CRM owns schema `public` (it was
-- empty) plus `private`; our own data stays in pipeline, content, reference, ops.
--
-- 1. The `http` extension (CRM avatar/favicon lookups) ships functions that
--    PUBLIC may execute: any login role (pipeline_agent, dashboard_ro, ops_app)
--    could then send HTTP from inside Postgres to the Docker network, the same
--    path 005 closed for pg_net. Keep it only for the roles the CRM uses.
-- 2. Functions in `public` default to EXECUTE for PUBLIC; some are SECURITY
--    DEFINER and read auth.users. Remove only the PUBLIC grant: Supabase's
--    default privileges already give anon/authenticated/service_role what the
--    CRM expects, and the CRM's own revokes (below) must stay in force.

do $$
declare f regprocedure;
begin
  if exists (select 1 from pg_extension where extname = 'http') then
    for f in select p.oid::regprocedure from pg_depend d join pg_proc p on p.oid = d.objid
             where d.refobjid = (select oid from pg_extension where extname = 'http')
               and d.classid = 'pg_proc'::regclass and d.deptype = 'e' loop
      execute format('revoke all on function %s from public', f);
      execute format('grant execute on function %s to postgres, authenticated, service_role', f);
    end loop;
  end if;
end $$;

revoke execute on all functions in schema public from public;
alter default privileges for role postgres in schema public revoke execute on functions from public;

-- The CRM's own restrictions (20260127140209_imports, 20261010054346_global_search),
-- re-stated so this file can never widen them.
do $$ begin
  if to_regprocedure('public.get_user_id_by_email(text)') is not null then
    revoke execute on function public.get_user_id_by_email(text) from anon, authenticated, public;
  end if;
  if to_regprocedure('public.global_search(text, text[], integer)') is not null then
    revoke execute on function public.global_search(text, text[], integer) from public, anon;
  end if;
end $$;

-- Belt and braces: our own roles never get CRM tables or functions directly.
do $$
declare r text;
begin
  foreach r in array array['pipeline_agent', 'dashboard_ro', 'ops_app'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on all tables in schema public from %I', r);
      execute format('revoke all on all functions in schema public from %I', r);
      if to_regnamespace('private') is not null then
        execute format('revoke all on schema private from %I', r);
      end if;
    end if;
  end loop;
end $$;
