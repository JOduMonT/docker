-- 006: yes-decks question cards and modifier word lists (content schema).
-- SCHEMA ONLY. The card text is paid course material (Igor Ledochowski, YES
-- Decks): it is never put in this public repo. Rows are loaded from the
-- private merged file Shared\Data\yes-decks\merged.json with
--   python <Shared>\product-pipeline\tools\pipeline_db.py load-yes-decks
-- (runs as postgres; agents and Appsmith only read). Idempotent.

create table if not exists content.yes_cards (
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
create index if not exists yes_cards_category on content.yes_cards (lower(category));

create table if not exists content.yes_modifiers (
  category text not null,
  idx      smallint not null check (idx >= 0),
  word     text not null check (length(trim(word)) > 0),
  primary key (category, idx),
  unique (category, word)
);

comment on table content.yes_cards is
  'YES Decks question cards (paid course material: private, quote briefly). Printed typos kept on purpose.';
comment on table content.yes_modifiers is 'YES Decks modifier word lists per category.';

alter table content.yes_cards enable row level security;
alter table content.yes_modifiers enable row level security;
revoke all on content.yes_cards, content.yes_modifiers from anon, authenticated, public;

-- Reference data: both roles read, nobody but postgres writes.
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'pipeline_agent') then
    grant select on content.yes_cards, content.yes_modifiers to pipeline_agent;
    drop policy if exists pipeline_agent_read on content.yes_cards;
    create policy pipeline_agent_read on content.yes_cards for select to pipeline_agent using (true);
    drop policy if exists pipeline_agent_read on content.yes_modifiers;
    create policy pipeline_agent_read on content.yes_modifiers for select to pipeline_agent using (true);
  end if;
  if exists (select 1 from pg_roles where rolname = 'dashboard_ro') then
    grant select on content.yes_cards, content.yes_modifiers to dashboard_ro;
    drop policy if exists dashboard_ro_read on content.yes_cards;
    create policy dashboard_ro_read on content.yes_cards for select to dashboard_ro using (true);
    drop policy if exists dashboard_ro_read on content.yes_modifiers;
    create policy dashboard_ro_read on content.yes_modifiers for select to dashboard_ro using (true);
  end if;
end $$;
