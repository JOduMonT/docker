-- 027: close the last RLS gaps and keep our schemas off the Data API (JDmnT move, 2026-11-16).
-- kobo.briefs and ops.data_store_debt were the only tables without RLS. Their
-- readers: nocodb_ro (grants from 009/014). Writers: postgres only (owner,
-- bypasses RLS), e.g. wiki/scripts/data_store_reconcile.py reads as owner.
-- Hosted Supabase exposes only public/graphql_public through PostgREST; this
-- file also removes any grant anon/authenticated/service_role could have on
-- our schemas, so they stay unreachable even if a schema is exposed by mistake.
-- Idempotent.

alter table kobo.briefs enable row level security;
alter table ops.data_store_debt enable row level security;
drop policy if exists nocodb_ro_read on kobo.briefs;
create policy nocodb_ro_read on kobo.briefs for select to nocodb_ro using (true);
drop policy if exists nocodb_ro_read on ops.data_store_debt;
create policy nocodb_ro_read on ops.data_store_debt for select to nocodb_ro using (true);

do $$
declare s text; r text;
begin
  foreach s in array array['books','content','core','courses','kobo','ops','pipeline','reference','research'] loop
    foreach r in array array['anon','authenticated','service_role'] loop
      if exists (select 1 from pg_roles where rolname = r) then
        execute format('revoke all on schema %I from %I', s, r);
        execute format('revoke all on all tables in schema %I from %I', s, r);
        execute format('revoke all on all sequences in schema %I from %I', s, r);
        execute format('revoke all on all functions in schema %I from %I', s, r);
      end if;
    end loop;
  end loop;
end $$;

-- Check (expect every row false):
--   select s, r, has_schema_privilege(r, s, 'USAGE')
--   from unnest(array['books','content','core','courses','kobo','ops','pipeline','reference','research']) s,
--        unnest(array['anon','authenticated','service_role']) r;
