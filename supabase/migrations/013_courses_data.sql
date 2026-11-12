-- 013_courses_data.sql
-- ai-training-courses/data CSVs → courses schema (Jon-approved data-store migration).
-- The courses schema + rehearsal_runs already exist (010).

create table if not exists courses.catalog (
  id          bigint generated always as identity primary key,
  legacy_id   text,
  course      text,
  proposed_by text,
  days        text,
  format      text,
  description text,
  stage       text,
  stage_no    int,
  priority    text,
  next_step   text,
  owner       text,
  updated     text
);

create table if not exists courses.notes (
  id        bigint generated always as identity primary key,
  course_id text,
  note      text,
  source    text
);

create table if not exists courses.references (
  id        bigint generated always as identity primary key,
  course_id text,
  ref_type  text,
  title     text,
  author    text,
  link      text,
  use_for   text,
  verified  text
);

create table if not exists courses.stages (
  stage_no int primary key,
  stage    text,
  meaning  text
);

grant usage on schema courses to nocodb_ro;
grant select on courses.catalog, courses.notes, courses.references, courses.stages to nocodb_ro;
