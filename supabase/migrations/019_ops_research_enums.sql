-- 019_ops_research_enums.sql  (apply as postgres, the apply.py default)
-- Step 2b of the enum conversion: ops.data_store_debt and research.triage fixed-list columns -> enums
-- (NocoDB Single select / Kanban). Value lists = the existing CHECKs. No views depend on these.

do $$
declare
  spec text[][] := array[
    ['ops','debt_status',         'pending,reviewing,migrating,migrated,kept,delete-approved'],
    ['ops','debt_decision',       'migrate,keep,delete'],
    ['research','triage_when',    'Now,Next,Later,Never'],
    ['research','triage_moscow',  'Must,Should,Could,Won''t']];
  cols text[][] := array[
    ['ops.data_store_debt','status','ops.debt_status'], ['ops.data_store_debt','decision','ops.debt_decision'],
    ['research.triage','when_bucket','research.triage_when'], ['research.triage','moscow','research.triage_moscow']];
  i int; labels text; d text;
begin
  for i in 1 .. array_length(spec, 1) loop
    if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                   where n.nspname = spec[i][1] and t.typname = spec[i][2]) then
      select string_agg(quote_literal(l), ',') into labels from unnest(string_to_array(spec[i][3], ',')) l;
      execute format('create type %I.%I as enum (%s)', spec[i][1], spec[i][2], labels);
      execute format('create cast (text as %I.%I) with inout as assignment', spec[i][1], spec[i][2]);
    end if;
  end loop;
  alter table ops.data_store_debt drop constraint if exists data_store_debt_status_check,
                                  drop constraint if exists data_store_debt_decision_check;
  alter table research.triage drop constraint if exists triage_when_bucket_check,
                              drop constraint if exists triage_moscow_check;
  for i in 1 .. array_length(cols, 1) loop
    select pg_get_expr(ad.adbin, ad.adrelid) into d
      from pg_attrdef ad join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
      where ad.adrelid = cols[i][1]::regclass and a.attname = cols[i][2];
    if d is not null then execute format('alter table %s alter column %I drop default', cols[i][1], cols[i][2]); end if;
    execute format('alter table %s alter column %I type %s using %I::%s',
                   cols[i][1], cols[i][2], cols[i][3], cols[i][2], cols[i][3]);
    if d is not null then
      execute format('alter table %s alter column %I set default %s', cols[i][1], cols[i][2], regexp_replace(d, '::text$', ''));
    end if;
  end loop;
end $$;

grant usage on type ops.debt_status, ops.debt_decision to nocodb_ro;
grant usage on type research.triage_when, research.triage_moscow to pipeline_agent, nocodb_ro;
