-- 014_kobo.sql
-- kobo-panel/data/brief.json → kobo schema (Jon-approved data-store migration).
create schema if not exists kobo;

create table if not exists kobo.briefs (
  id           bigint generated always as identity primary key,
  brief_date   date,
  generated_at timestamptz,
  headline     text,
  data         jsonb not null
);

grant usage on schema kobo to nocodb_ro;
grant select on kobo.briefs to nocodb_ro;
