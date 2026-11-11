-- ops.tasks: one shared task list for Jon and every agent (anti-drift core).
-- A task can only be 'done' with proof (link, commit, test result).
create schema if not exists ops;

create table if not exists ops.tasks (
  id          bigint generated always as identity primary key,
  title       text not null check (length(trim(title)) > 0),
  detail      text,
  owner       text not null,                       -- agent name or 'Jon'
  requested_by text not null default 'Jon',
  status      text not null default 'todo'
              check (status in ('todo','in_progress','blocked','review','done','cancelled')),
  priority    text not null default 'next' check (priority in ('now','next','later')),
  due         date,
  proof       text,                                -- required when done
  blocker     text,                                -- required when blocked
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint done_needs_proof    check (status <> 'done'    or coalesce(trim(proof),'')   <> ''),
  constraint blocked_needs_reason check (status <> 'blocked' or coalesce(trim(blocker),'') <> '')
);

create index if not exists tasks_owner_status on ops.tasks (owner, status);

-- Every change is logged: who could not quietly rewrite history.
create table if not exists ops.task_events (
  id         bigint generated always as identity primary key,
  task_id    bigint not null references ops.tasks(id) on delete cascade,
  at         timestamptz not null default now(),
  old_status text,
  new_status text,
  changed_by text,
  snapshot   jsonb not null
);

create or replace function ops.tasks_touch() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create or replace function ops.tasks_log() returns trigger language plpgsql as $$
begin
  insert into ops.task_events (task_id, old_status, new_status, changed_by, snapshot)
  values (new.id,
          case when tg_op = 'UPDATE' then old.status end,
          new.status,
          coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'agent', current_user),
          to_jsonb(new));
  return new;
end $$;

drop trigger if exists tasks_touch on ops.tasks;
create trigger tasks_touch before update on ops.tasks
  for each row execute function ops.tasks_touch();

drop trigger if exists tasks_log on ops.tasks;
create trigger tasks_log after insert or update on ops.tasks
  for each row execute function ops.tasks_log();

-- Stale work: in progress or blocked with no update for 2 days.
create or replace view ops.stale_tasks as
  select * from ops.tasks
  where status in ('in_progress','blocked','review')
    and updated_at < now() - interval '2 days';

-- Not exposed to anon; agents and Appsmith use a dedicated role (see 002).
alter table ops.tasks enable row level security;
alter table ops.task_events enable row level security;
revoke all on schema ops from anon, authenticated;
