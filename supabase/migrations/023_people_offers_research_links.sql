-- 023_people_offers_research_links.sql  (apply as postgres, the apply.py default; after 022)
-- Jon 2026-11-12 (item 4 of the linking work):
--   a. core.people_agents: who did what (auto-created names get kind 'unknown'; no alias handling, so
--      'jon' and 'Jon' would be two rows; renaming a person needs a migration because the log FKs pin names).
--   a. core.people_agents: who did what. FKs on the existing free-text people columns; a new name is
--      auto-created by trigger, so writers are untouched and never fail. (The content/pipeline
--      'owner' columns hold the tenant, e.g. client0, not a person: not linked.)
--   b. core.offer_types + link tables for the comma lists in content.stories.offers and the
--      'webinar: ...' / '... coaching' text in content.posts.offer (filled by trigger, no post update).
--   c. research.triage_courses: which research item feeds which course (empty; agents or Jon fill it).

-- a. People and agents -------------------------------------------------------------------------
create table if not exists core.people_agents (
  name       text primary key,
  kind       text not null default 'unknown' check (kind in ('person','agent','db-role','tenant','unknown')),
  agent_id   text,              -- OpenBot agent id, for agents
  note       text,
  created_at timestamptz not null default now()
);
-- Only non-personal rows here (this repo is public). Names, kinds, agent ids and notes for people and
-- agents live in the git-ignored 023_people_agents_seed.sql.local (apply it after this file).
insert into core.people_agents (name, kind, note) values
  ('postgres', 'db-role', 'migrations and admin'),
  ('pipeline_agent', 'db-role', 'agent write role'),
  ('ops_app', 'db-role', 'ops task app role'),
  ('client0', 'tenant', 'default tenant')
  on conflict (name) do nothing;
-- every name already in use (exact text, so nothing is renamed)
insert into core.people_agents (name)
  select v from (
    select owner v from ops.tasks union select requested_by from ops.tasks
    union select changed_by from ops.task_events union select changed_by from content.post_events
    union select changed_by from content.engagement_events
    union select owner from courses.catalog union select proposed_by from courses.catalog
    union select requester from pipeline.runs) x
  where v is not null on conflict (name) do nothing;

create or replace function core.ensure_person(p_name text) returns void
  language sql set search_path = core, pg_temp as $$
  insert into core.people_agents (name) select p_name where p_name is not null on conflict (name) do nothing
$$;
-- one generic trigger: TG_ARGV lists the people columns of the table
create or replace function core.people_fill() returns trigger
  language plpgsql set search_path = core, pg_temp as $$
declare c text; v text;
begin
  foreach c in array tg_argv loop
    v := to_jsonb(new) ->> c;
    perform core.ensure_person(v);
  end loop;
  return new;
end $$;

do $$
declare
  spec text[][] := array[
    ['ops.tasks','owner'], ['ops.tasks','requested_by'], ['ops.task_events','changed_by'],
    ['content.post_events','changed_by'], ['content.engagement_events','changed_by'],
    ['courses.catalog','owner'], ['courses.catalog','proposed_by'], ['pipeline.runs','requester']];
  i int; tbl text; fk text;
begin
  for i in 1 .. array_length(spec, 1) loop
    tbl := spec[i][1];
    fk := replace(tbl, '.', '_') || '_' || spec[i][2] || '_person_fk';
    if not exists (select 1 from pg_constraint where conname = fk) then
      execute format('alter table %s add constraint %I foreign key (%I) references core.people_agents (name)',
                     tbl, fk, spec[i][2]);
    end if;
  end loop;
end $$;
drop trigger if exists people_fill on ops.tasks;
create trigger people_fill before insert or update of owner, requested_by on ops.tasks
  for each row execute function core.people_fill('owner', 'requested_by');
drop trigger if exists people_fill on ops.task_events;
create trigger people_fill before insert on ops.task_events for each row execute function core.people_fill('changed_by');
drop trigger if exists people_fill on content.post_events;
create trigger people_fill before insert on content.post_events for each row execute function core.people_fill('changed_by');
drop trigger if exists people_fill on content.engagement_events;
create trigger people_fill before insert on content.engagement_events for each row execute function core.people_fill('changed_by');
drop trigger if exists people_fill on courses.catalog;
create trigger people_fill before insert or update of owner, proposed_by on courses.catalog
  for each row execute function core.people_fill('owner', 'proposed_by');
drop trigger if exists people_fill on pipeline.runs;
create trigger people_fill before insert or update of requester on pipeline.runs
  for each row execute function core.people_fill('requester');

-- b. Offer types ---------------------------------------------------------------------------------
create table if not exists core.offer_types (
  offer_type text primary key,
  note       text
);
insert into core.offer_types (offer_type, note) values
  ('webinar', 'live online session'), ('workshop', 'hands-on group session'),
  ('digital-asset', 'checklist, template, guide'), ('coaching', 'one-to-one or small-group coaching'),
  ('course', 'multi-session class'), ('consulting', 'advisory engagement')
  on conflict do nothing;

-- free text -> offer types: comma list for stories; for posts the 'type: ...' prefix or a type word
create or replace function core.offer_types_in(p_text text) returns setof text
  language sql stable set search_path = core, pg_temp as $$
  select distinct o.offer_type from core.offer_types o, unnest(string_to_array(lower(coalesce(p_text, '')), ',')) part
  where trim(part) = o.offer_type
     or split_part(trim(part), ':', 1) = o.offer_type
     or (o.offer_type in ('webinar', 'workshop', 'coaching')       -- word match only for unambiguous types
         and trim(part) ~ ('(^|[^a-z])' || o.offer_type || '([^a-z]|$)'))
$$;

create table if not exists content.story_offer_types (
  story_id   text not null references content.stories (story_id) on delete cascade,
  offer_type text not null references core.offer_types (offer_type),
  primary key (story_id, offer_type)
);
create table if not exists content.post_offer_types (
  post_id    text not null references content.posts (post_id) on delete cascade,
  offer_type text not null references core.offer_types (offer_type),
  primary key (post_id, offer_type)
);
create or replace function content.story_offer_types_sync() returns trigger
  language plpgsql set search_path = content, core, pg_temp as $$
begin
  delete from content.story_offer_types where story_id = new.story_id;
  insert into content.story_offer_types select new.story_id, t from core.offer_types_in(new.offers) t on conflict do nothing;
  return null;
end $$;
create or replace function content.post_offer_types_sync() returns trigger
  language plpgsql set search_path = content, core, pg_temp as $$
begin
  delete from content.post_offer_types where post_id = new.post_id;
  insert into content.post_offer_types select new.post_id, t from core.offer_types_in(new.offer) t on conflict do nothing;
  return null;
end $$;
drop trigger if exists stories_offer_types on content.stories;
create trigger stories_offer_types after insert or update of offers on content.stories
  for each row execute function content.story_offer_types_sync();
drop trigger if exists posts_offer_types on content.posts;
create trigger posts_offer_types after insert or update of offer on content.posts
  for each row execute function content.post_offer_types_sync();
insert into content.story_offer_types select s.story_id, t from content.stories s, core.offer_types_in(s.offers) t on conflict do nothing;
insert into content.post_offer_types select p.post_id, t from content.posts p, core.offer_types_in(p.offer) t on conflict do nothing;

-- c. Research feeding courses -----------------------------------------------------------------
create table if not exists research.triage_courses (
  triage_id  bigint not null references research.triage (id) on delete cascade,
  course_id  text not null references courses.catalog (legacy_id) on delete cascade,
  note       text,
  created_at timestamptz not null default now(),
  primary key (triage_id, course_id)
);

-- Grants and RLS ---------------------------------------------------------------------------------
grant select, insert on core.people_agents to pipeline_agent, ops_app;
grant select on core.people_agents, core.offer_types to pipeline_agent, ops_app, dashboard_ro, nocodb_ro;
grant execute on function core.ensure_person(text), core.offer_types_in(text) to pipeline_agent, ops_app;
grant select, insert, delete on content.story_offer_types, content.post_offer_types to pipeline_agent;
grant select on content.story_offer_types, content.post_offer_types to dashboard_ro, nocodb_ro;
grant select, insert, delete on research.triage_courses to pipeline_agent;
grant select on research.triage_courses to nocodb_ro;
do $$
declare t text;
begin
  foreach t in array array['core.people_agents','core.offer_types','content.story_offer_types',
                           'content.post_offer_types','research.triage_courses'] loop
    execute format('alter table %s enable row level security', t);
    execute format('drop policy if exists pipeline_agent_write on %s', t);
    execute format('create policy pipeline_agent_write on %s for all to pipeline_agent using (true) with check (true)', t);
    execute format('drop policy if exists ops_app_write on %s', t);
    execute format('create policy ops_app_write on %s for all to ops_app using (true) with check (true)', t);
    execute format('drop policy if exists read_only on %s', t);
    execute format('create policy read_only on %s for select to nocodb_ro, dashboard_ro using (true)', t);
  end loop;
end $$;
