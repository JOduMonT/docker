-- 012_books.sql
-- books-triage-pipeline reports → books schema (Jon-approved data-store migration).
create schema if not exists books;

create table if not exists books.changes (
  id         bigint generated always as identity primary key,
  changed_at timestamptz,
  batch_id   text,
  book_id    bigint,
  title      text,
  field      text,
  before     text,
  after      text,
  source     text
);

create table if not exists books.research_log (
  id              bigint generated always as identity primary key,
  at              timestamptz,
  source          text,
  book_id         bigint,
  title           text,
  field           text,
  current         text,
  proposed        text,
  meta_confidence numeric,
  action          text
);

create table if not exists books.triage (
  id                 bigint generated always as identity primary key,
  at                 timestamptz,
  filename           text,
  book_id            bigint,
  decision           text,
  domain             text,
  moscow             text,
  confidence         numeric,
  is_new_domain      boolean,
  language           text,
  pages              int,
  words              int,
  source_hash        text,
  reason             text,
  wrote_back         boolean,
  workspace_priority int
);

create table if not exists books.taxonomy (
  id          bigint generated always as identity primary key,
  slug        text,
  description text,
  created     date,
  last_seen   date,
  seen_count  int
);

grant usage on schema books to nocodb_ro;
grant select on books.changes, books.research_log, books.triage, books.taxonomy to nocodb_ro;
