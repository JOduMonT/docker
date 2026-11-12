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

-- Row-level security, matching the pattern on pipeline.tasks/ops.tasks.
alter table courses.rehearsal_runs enable row level security;
drop policy if exists pipeline_agent_write on courses.rehearsal_runs;
create policy pipeline_agent_write on courses.rehearsal_runs
  for all to pipeline_agent using (true) with check (true);
drop policy if exists nocodb_ro_read on courses.rehearsal_runs;
create policy nocodb_ro_read on courses.rehearsal_runs
  for select to nocodb_ro using (true);

-- Jon sees it in NocoDB through the read-only role (explicit grants, no default privileges).
grant usage on schema courses to nocodb_ro;
grant select on courses.rehearsal_runs to nocodb_ro;

-- Chiron logs runs through the agent write role (append-only: no DELETE).
grant usage on schema courses to pipeline_agent;
grant select, insert, update on courses.rehearsal_runs to pipeline_agent;
