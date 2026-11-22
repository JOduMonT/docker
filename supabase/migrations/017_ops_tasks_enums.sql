-- 017_ops_tasks_enums.sql
-- Fixed-list text columns -> Postgres enums, so NocoDB (schema edit OFF) shows them as
-- Single select and allows Kanban views (Jon, 2026-11-12). Step 1: ops.tasks only.
-- Same text values; the enum replaces the value-list CHECK constraints.
-- Writers that send a text-typed value keep working through an assignment cast text -> enum
-- (string literals and untyped parameters need no cast at all).

do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'ops' and t.typname = 'task_status') then
    create type ops.task_status as enum ('todo','in_progress','blocked','review','done','cancelled');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'ops' and t.typname = 'task_priority') then
    create type ops.task_priority as enum ('now','next','later');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_cast where castsource = 'text'::regtype and casttarget = 'ops.task_status'::regtype) then
    create cast (text as ops.task_status) with inout as assignment;
  end if;
  if not exists (select 1 from pg_cast where castsource = 'text'::regtype and casttarget = 'ops.task_priority'::regtype) then
    create cast (text as ops.task_priority) with inout as assignment;
  end if;
end $$;

-- The view and the CHECKs compare status with text literals; drop, convert, recreate.
drop view if exists ops.stale_tasks;
alter table ops.tasks drop constraint if exists tasks_status_check;
alter table ops.tasks drop constraint if exists tasks_priority_check;
alter table ops.tasks drop constraint if exists done_needs_proof;
alter table ops.tasks drop constraint if exists blocked_needs_reason;

alter table ops.tasks alter column status drop default, alter column priority drop default;
alter table ops.tasks
  alter column status   type ops.task_status   using status::ops.task_status,
  alter column priority type ops.task_priority using priority::ops.task_priority;
alter table ops.tasks alter column status set default 'todo', alter column priority set default 'next';

alter table ops.tasks add constraint done_needs_proof
  check (status <> 'done' or coalesce(trim(proof), '') <> '');
alter table ops.tasks add constraint blocked_needs_reason
  check (status <> 'blocked' or coalesce(trim(blocker), '') <> '');

create view ops.stale_tasks as
  select id, title, detail, owner, requested_by, status, priority, due, proof, blocker, created_at, updated_at
  from ops.tasks
  where status in ('in_progress', 'blocked', 'review') and updated_at < now() - interval '2 days';

-- Re-grant the view (dropped above) as before, and the new types to the roles that read/write it.
grant select on ops.stale_tasks to nocodb_ro, ops_app;
grant usage on type ops.task_status, ops.task_priority to nocodb_ro, ops_app;
