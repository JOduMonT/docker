-- 010_rehearsal_runs.sql
-- Course rehearsal log (Chiron grades, Jon practises). Replaces the log table at the
-- bottom of ai-training-courses/rehearsals/protocol.md (doctrine: data lives in Supabase).
create schema if not exists courses;

create table if not exists courses.rehearsal_runs (
  id          bigint generated always as identity primary key,
  course      text not null check (length(trim(course)) > 0),
  run_number  integer not null check (run_number > 0),
  run_date    date not null,
  timing      text,                 -- end vs plan, e.g. "+3 min"
  talk_ratio  text,                 -- e.g. "40%"
  lowest_rows text,                 -- rubric rows that scored lowest
  improvement text,                 -- the one improvement for the next run
  applied     boolean not null default false,
  created_at  timestamptz not null default now(),
  constraint rehearsal_runs_course_run_uniq unique (course, run_number)
);

-- Jon sees it in NocoDB through the read-only role (explicit grants, no default privileges).
grant usage on schema courses to nocodb_ro;
grant select on courses.rehearsal_runs to nocodb_ro;
