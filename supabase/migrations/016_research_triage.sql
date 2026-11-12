-- 016_research_triage.sql
-- wiki research/triage/triage.csv -> research.triage (Jon 2026-11-12: migrate, then delete the file).
-- Writer: the Triage Curator routine (one row per triaged raw/ item), through wiki scripts/triage_ledger.py
-- as the agent role pipeline_agent. Append-only ledger: SELECT + INSERT, no UPDATE/DELETE.
-- Readers: the routine's "already triaged?" check (item is unique) and Jon in NocoDB (nocodb_ro).
create schema if not exists research;

create table if not exists research.triage (
  id                 bigint generated always as identity primary key,
  at                 timestamptz not null,
  item               text not null check (length(trim(item)) > 0),
  source_type        text,
  decision           text,
  domain             text,
  moscow             text check (moscow in ('Must','Should','Could','Won''t')),
  when_bucket        text check (when_bucket in ('Now','Next','Later','Never')),   -- CSV column "when"
  confidence         numeric check (confidence between 0 and 1),
  is_new_domain      boolean,                                                     -- CSV "unchecked" -> NULL
  language           text,
  accuracy           smallint check (accuracy between 0 and 3),
  novelty            smallint check (novelty between 0 and 3),
  substance          smallint check (substance between 0 and 3),
  actionability      smallint check (actionability between 0 and 3),
  total              smallint check (total between 0 and 12),
  fit_to_jon         smallint check (fit_to_jon between 0 and 3),
  reason             text,
  workspace_priority smallint,
  created_at         timestamptz not null default now(),
  -- The routine checks "already triaged?" while the file is still in raw/, but the row stores
  -- the post-move path (raw/archive/...), so identity is the file name, not the full path.
  item_name          text generated always as (regexp_replace(item, '^.*[/\\]', '')) stored,
  constraint research_triage_item_uniq unique (item),
  constraint research_triage_item_name_uniq unique (item_name),
  constraint research_triage_total_sum check (total = accuracy + novelty + substance + actionability)
);

alter table research.triage enable row level security;
drop policy if exists pipeline_agent_write on research.triage;
create policy pipeline_agent_write on research.triage for all to pipeline_agent using (true) with check (true);
drop policy if exists nocodb_ro_read on research.triage;
create policy nocodb_ro_read on research.triage for select to nocodb_ro using (true);

grant usage on schema research to pipeline_agent, nocodb_ro;
grant select, insert on research.triage to pipeline_agent;
grant select on research.triage to nocodb_ro;
