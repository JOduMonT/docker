-- 021_links_courses_content.sql  (apply as postgres, the apply.py default)
-- Jon 2026-11-12: "the DB must link my thinking", so real foreign keys (NocoDB shows them as Links).
-- Rule: writers are never broken. Free-text columns stay; a link column is added beside them and
-- filled by trigger, and unknown values never fail a write (they leave the link NULL or auto-create it).
--   1. books.triage.moscow_bucket: generated enum (Kanban by MoSCoW); the writer's moscow text is untouched.
--   2. courses.notes / courses.references .course_id -> courses.catalog(legacy_id) (values already match).
--   3. courses.rehearsal_runs.course_id -> catalog, filled from the course title.
--   4. content.campaigns (new): one row per posts.campaign, optionally linked to a course and a narrative;
--      content.posts.campaign -> campaigns (unknown campaign auto-created), posts.narrative_id -> narratives.

-- 1. MoSCoW bucket for books ---------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'books' and t.typname = 'moscow_bucket') then
    create type books.moscow_bucket as enum ('Must', 'Should', 'Could', 'Won''t', 'Unsorted');
  end if;
end $$;
alter table books.triage add column if not exists moscow_bucket books.moscow_bucket
  generated always as (
    case lower(regexp_replace(coalesce(moscow, ''), '[^A-Za-z]', '', 'g'))
      when 'must' then 'Must'::books.moscow_bucket
      when 'should' then 'Should'::books.moscow_bucket
      when 'could' then 'Could'::books.moscow_bucket
      when 'wont' then 'Won''t'::books.moscow_bucket
      else 'Unsorted'::books.moscow_bucket
    end) stored;
grant usage on type books.moscow_bucket to pipeline_agent, nocodb_ro;

-- 2. Course notes and references -> catalog --------------------------------------------------
alter table courses.catalog add constraint catalog_legacy_id_key unique using index catalog_legacy_id_uniq;
alter table courses.notes add constraint notes_course_fk
  foreign key (course_id) references courses.catalog (legacy_id);
alter table courses."references" add constraint references_course_fk
  foreign key (course_id) references courses.catalog (legacy_id);

-- 3. Rehearsal runs -> catalog (course title stays; course_id filled when the title matches) --
alter table courses.rehearsal_runs add column if not exists course_id text
  references courses.catalog (legacy_id);
create or replace function courses.rehearsal_runs_link() returns trigger
  language plpgsql security definer set search_path = courses, pg_temp as $$
begin
  if new.course_id is null then
    select legacy_id into new.course_id from courses.catalog
      where lower(trim(course)) = lower(trim(new.course)) limit 1;
  end if;
  return new;
end $$;
drop trigger if exists rehearsal_runs_link on courses.rehearsal_runs;
create trigger rehearsal_runs_link before insert or update of course, course_id on courses.rehearsal_runs
  for each row execute function courses.rehearsal_runs_link();
grant update (course_id) on courses.rehearsal_runs to pipeline_agent;

-- 4. Campaigns, posts -> campaign and narrative ---------------------------------------------
create table if not exists content.campaigns (
  campaign_id  text primary key,   -- any text, as posts.campaign has no format rule
  name         text,
  course_id    text references courses.catalog (legacy_id),   -- the course this campaign promotes, if any
  narrative_id text references content.narratives (narrative_id),
  created_at   timestamptz not null default now()
);
insert into content.campaigns (campaign_id, name)
  select distinct campaign, initcap(replace(campaign, '-', ' ')) from content.posts where campaign is not null
  on conflict do nothing;
-- Known links today: the Spot the Hallucination webinar campaign = course 15 and its offer narrative.
update content.campaigns c set
  course_id = (select legacy_id from courses.catalog where lower(course) = lower(replace(c.campaign_id, '-', ' '))),
  narrative_id = (select narrative_id from content.narratives n where n.offer = c.campaign_id)
  where course_id is null or narrative_id is null;

alter table content.campaigns enable row level security;
drop policy if exists pipeline_agent_all on content.campaigns;
create policy pipeline_agent_all on content.campaigns for all to pipeline_agent using (true) with check (true);
drop policy if exists dashboard_ro_read on content.campaigns;
create policy dashboard_ro_read on content.campaigns for select to dashboard_ro using (true);
drop policy if exists nocodb_ro_read on content.campaigns;
create policy nocodb_ro_read on content.campaigns for select to nocodb_ro using (true);
grant select, insert, update on content.campaigns to pipeline_agent;
grant select on content.campaigns to dashboard_ro, nocodb_ro;

alter table content.posts add column if not exists narrative_id text references content.narratives (narrative_id);

-- Fills the links on every insert/update; never raises for an unknown value.
create or replace function content.posts_links() returns trigger
  language plpgsql security definer set search_path = content, pg_temp as $$
begin
  if new.campaign is not null then
    insert into content.campaigns (campaign_id, name)
      values (new.campaign, initcap(replace(new.campaign, '-', ' '))) on conflict do nothing;
  end if;
  if new.narrative_id is null then
    select n.narrative_id into new.narrative_id from content.narratives n
      where n.source_path = new.narrative
         or (new.narrative is null and n.offer = new.campaign)
      order by (n.source_path = new.narrative) desc limit 1;
  end if;
  return new;
end $$;
drop trigger if exists posts_links on content.posts;
-- runs after posts_before (BEFORE triggers fire in name order)
create trigger posts_links before insert or update of campaign, narrative, narrative_id on content.posts
  for each row execute function content.posts_links();

-- FK on the existing free-text campaign column: the trigger above creates every non-null value first.
alter table content.posts add constraint posts_campaign_fk
  foreign key (campaign) references content.campaigns (campaign_id);

-- Backfill narrative_id on existing posts without firing the frozen-content and history triggers:
-- this is a schema backfill, not an edit of an approved post (no post_events row, updated_at kept).
alter table content.posts disable trigger posts_before, disable trigger posts_log;
update content.posts p set narrative_id = n.narrative_id
  from content.narratives n
  where p.narrative_id is null
    and (n.source_path = p.narrative or (p.narrative is null and n.offer = p.campaign));
alter table content.posts enable trigger posts_before, enable trigger posts_log;
