-- 002: ops_app, the role 001/017/022/023 grant to. Committed twin of the
-- git-ignored 002_ops_app_role.sql.local (which also set a local password).
-- No client logs in as ops_app (checked 2026-11-16: only tests name it), so a
-- database that creates it here gets a NOLOGIN role with no password.
-- Idempotent; an existing ops_app (local) keeps its login and password.

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'ops_app') then
    create role ops_app nologin;
  end if;
end $$;

grant usage on schema ops to ops_app;
grant select, insert, update on ops.tasks to ops_app;
grant select on ops.task_events, ops.stale_tasks to ops_app;
grant insert on ops.task_events to ops_app;
grant usage on all sequences in schema ops to ops_app;
drop policy if exists ops_app_all on ops.tasks;
create policy ops_app_all on ops.tasks for all to ops_app using (true) with check (true);
drop policy if exists ops_app_read on ops.task_events;
create policy ops_app_read on ops.task_events for select to ops_app using (true);
drop policy if exists ops_app_log on ops.task_events;
create policy ops_app_log on ops.task_events for insert to ops_app with check (true);
