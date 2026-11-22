-- 006: yes-decks question cards and modifier word lists, in schema `reference`.
-- SCHEMA ONLY. The card text is paid course material (Igor Ledochowski, YES
-- Decks): it is never put in this public repo. Rows are loaded from the
-- private merged file Shared\Data\yes-decks\merged.json with
--   python <Shared>\product-pipeline\tools\pipeline_db.py load-yes-decks
-- (runs as postgres; agents only read). Idempotent.
--
-- Own schema on purpose: only pipeline_agent may read it. dashboard_ro (Appsmith,
-- behind the tunnel) has no USAGE here, and 004's grants cover only pipeline and
-- content, so re-running 004 can never re-open it.

create schema if not exists reference;
revoke all on schema reference from public, anon, authenticated;

-- First apply put the tables in content: move them (rows kept).
do $$ begin
  if to_regclass('content.yes_cards') is not null and to_regclass('reference.yes_cards') is null then
    alter table content.yes_cards set schema reference;
  end if;
  if to_regclass('content.yes_modifiers') is not null and to_regclass('reference.yes_modifiers') is null then
    alter table content.yes_modifiers set schema reference;
  end if;
end $$;

create table if not exists reference.yes_cards (
  card_no       smallint primary key check (card_no > 0),
  deck          text not null,
  volume        smallint,
  category      text not null,
  template      text not null check (length(trim(template)) > 0),
  examples      text[] not null check (cardinality(examples) > 0),
  -- a differing copy found at the 2026-11-11 merge, kept next to the printed text
  alt_examples  jsonb,
  conflict_note text,
  unique (deck, volume, category, template)
);
create index if not exists yes_cards_category on reference.yes_cards (lower(category));

create table if not exists reference.yes_modifiers (
  category text not null,
  idx      smallint not null check (idx >= 0),
  word     text not null check (length(trim(word)) > 0),
  primary key (category, idx),
  unique (category, word)
);

comment on table reference.yes_cards is
  'YES Decks question cards (paid course material: private, quote briefly). Printed typos kept on purpose.';
comment on table reference.yes_modifiers is 'YES Decks modifier word lists per category.';

alter table reference.yes_cards enable row level security;
alter table reference.yes_modifiers enable row level security;
revoke all on reference.yes_cards, reference.yes_modifiers from anon, authenticated, public;

do $$ begin
  if exists (select 1 from pg_roles where rolname = 'dashboard_ro') then
    revoke all on schema reference from dashboard_ro;
    revoke all on reference.yes_cards, reference.yes_modifiers from dashboard_ro;
    drop policy if exists dashboard_ro_read on reference.yes_cards;
    drop policy if exists dashboard_ro_read on reference.yes_modifiers;
  end if;
  if exists (select 1 from pg_roles where rolname = 'pipeline_agent') then
    grant usage on schema reference to pipeline_agent;
    grant select on reference.yes_cards, reference.yes_modifiers to pipeline_agent;
    drop policy if exists pipeline_agent_read on reference.yes_cards;
    create policy pipeline_agent_read on reference.yes_cards for select to pipeline_agent using (true);
    drop policy if exists pipeline_agent_read on reference.yes_modifiers;
    create policy pipeline_agent_read on reference.yes_modifiers for select to pipeline_agent using (true);
  end if;
end $$;
