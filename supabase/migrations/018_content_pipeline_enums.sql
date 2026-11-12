-- 018_content_pipeline_enums.sql  (apply as postgres, the apply.py default: the 7 recreated views must stay owned by postgres)
-- (schema edit OFF) shows Single select and allows Kanban. Value lists = the existing CHECKs.
-- Same text values, no data change. Writers keep working: literals and untyped parameters need
-- no cast, and an assignment cast text -> enum covers text-typed values.
-- Dependent views are saved, dropped and recreated with the same definition, options and grants.

-- 1. Types, plus an assignment cast from text for each.
do $$
declare
  spec text[][] := array[
    ['content','post_status',     'drafted,approved,posted,verified,skipped'],
    ['content','post_platform',   'linkedin,facebook,bluesky,mastodon,website'],
    ['content','post_format',     'carousel-pdf,image,text,video,link'],
    ['pipeline','run_state',      'running,passed,failed,no-go,sent-back'],
    ['pipeline','run_verdict',    'go,no-go'],
    ['pipeline','delivery_mode',  'self-serve,handover'],
    ['pipeline','source_type',    'file,url,text'],
    ['pipeline','framing',        'literal,job,shifted'],
    ['pipeline','evidence_type',  'pain,pay,opinion']];
  i int; labels text;
begin
  for i in 1 .. array_length(spec, 1) loop
    if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                   where n.nspname = spec[i][1] and t.typname = spec[i][2]) then
      select string_agg(quote_literal(l), ',') into labels from unnest(string_to_array(spec[i][3], ',')) l;
      execute format('create type %I.%I as enum (%s)', spec[i][1], spec[i][2], labels);
      execute format('create cast (text as %I.%I) with inout as assignment', spec[i][1], spec[i][2]);
    end if;
  end loop;
end $$;

-- 2. Save and drop the dependent views.
create temp table _views on commit drop as
  select c.oid::regclass::text as name, pg_get_viewdef(c.oid, true) as def, c.reloptions as opts, c.relacl as acl
  from pg_class c
  where c.oid in ('content.search_docs'::regclass, 'content.v_post_asset_reuse'::regclass,
                  'content.v_stories_hooks'::regclass, 'pipeline.v_runs'::regclass,
                  'pipeline.v_top_tasks'::regclass, 'pipeline.v_funnel'::regclass, 'pipeline.v_launch'::regclass);
do $$ declare v record; begin
  for v in select name from _views loop execute format('drop view %s', v.name); end loop;
end $$;

-- 3. CHECKs that compare these columns with text: drop (value lists become the enum; the rule checks are re-added below).
alter table content.posts drop constraint posts_status_check, drop constraint posts_platform_check,
  drop constraint posts_format_check, drop constraint approved_needs_approval_ref,
  drop constraint approved_needs_approved_at, drop constraint posted_needs_posted_at;
alter table pipeline.runs drop constraint runs_state_check, drop constraint runs_verdict_check,
  drop constraint runs_delivery_mode_check, drop constraint runs_source_type_check, drop constraint runs_framing_check;
alter table pipeline.evidence drop constraint evidence_type_check;

-- 4. Convert, keeping each column's default (re-set as the same text value).
do $$
declare
  cols text[][] := array[
    ['content.posts','status','content.post_status'], ['content.posts','platform','content.post_platform'],
    ['content.posts','format','content.post_format'],
    ['pipeline.runs','state','pipeline.run_state'], ['pipeline.runs','verdict','pipeline.run_verdict'],
    ['pipeline.runs','delivery_mode','pipeline.delivery_mode'], ['pipeline.runs','source_type','pipeline.source_type'],
    ['pipeline.runs','framing','pipeline.framing'], ['pipeline.evidence','type','pipeline.evidence_type']];
  i int; d text;
begin
  for i in 1 .. array_length(cols, 1) loop
    select pg_get_expr(ad.adbin, ad.adrelid) into d
      from pg_attrdef ad join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
      where ad.adrelid = cols[i][1]::regclass and a.attname = cols[i][2];
    if d is not null then execute format('alter table %s alter column %I drop default', cols[i][1], cols[i][2]); end if;
    execute format('alter table %s alter column %I type %s using %I::%s',
                   cols[i][1], cols[i][2], cols[i][3], cols[i][2], cols[i][3]);
    if d is not null then
      execute format('alter table %s alter column %I set default %s', cols[i][1], cols[i][2],
                     regexp_replace(d, '::text$', ''));
    end if;
  end loop;
end $$;

-- 5. The rule checks on content.posts, rewritten without text casts.
alter table content.posts
  add constraint approved_needs_approval_ref
    check (status not in ('approved','posted','verified') or coalesce(trim(approval_ref), '') <> ''),
  add constraint approved_needs_approved_at
    check (status not in ('approved','posted','verified') or approved_at is not null),
  add constraint posted_needs_posted_at
    check (status not in ('posted','verified') or posted_at is not null);

-- 6. content.posts_before calls content.status_rank(new.status): add the enum overload.
create or replace function content.status_rank(s content.post_status) returns integer
  language sql immutable as $$ select content.status_rank(s::text) $$;
grant execute on function content.status_rank(content.post_status) to pipeline_agent, dashboard_ro;

-- 7. Recreate the views (v_post_asset_reuse compared status with a text literal: rewritten).
update _views set def = replace(def, $q$status <> 'skipped'::text$q$, $q$status <> 'skipped'$q$)
  where name = 'content.v_post_asset_reuse';
do $$
declare v record; g record;
begin
  for v in select * from _views order by name loop
    execute format('create view %s %s as %s', v.name,
                   case when v.opts is null then '' else 'with (' || array_to_string(v.opts, ',') || ')' end, v.def);
    for g in select (aclexplode(v.acl)).* loop
      if g.grantee <> 0 and g.grantee <> (select oid from pg_roles where rolname = 'postgres') then
        execute format('grant %s on %s to %I', g.privilege_type, v.name, (select rolname from pg_roles where oid = g.grantee));
      end if;
    end loop;
  end loop;
end $$;

-- 8. Roles that read or write these tables may use the types.
grant usage on type content.post_status, content.post_platform, content.post_format,
  pipeline.run_state, pipeline.run_verdict, pipeline.delivery_mode, pipeline.source_type, pipeline.framing,
  pipeline.evidence_type to pipeline_agent, dashboard_ro, nocodb_ro;
