-- 004: roles for the pipeline/content schemas. No secrets in this file: the
-- passwords come from supabase/.env (PIPELINE_AGENT_PASSWORD,
-- DASHBOARD_RO_PASSWORD) as psql variables, set by migrations/apply.py.
--
--   pipeline_agent  OpenBot agents and the sync script: read/write.
--                   Event logs: read only (written by triggers).
--                   story_use: insert + read (append-only).
--                   engagement, posts: insert, update, read (no delete).
--   dashboard_ro    Appsmith: read only, every table and view.
-- Login through the pooler as <role>.<POOLER_TENANT_ID>, e.g. pipeline_agent.openbot.

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'pipeline_agent') then create role pipeline_agent login; end if;
  if not exists (select 1 from pg_roles where rolname = 'dashboard_ro')   then create role dashboard_ro login;   end if;
end $$;

-- Passwords are (re)set only when apply.py could not log in with the .env value:
-- re-setting an unchanged password gives it a new hash, and the pooler then
-- rejects the next login of every agent once (stale cached credentials).
-- The check goes through the pooler, whose cache can still accept a password the
-- database no longer has (e.g. after a direct ALTER ROLE ... PASSWORD). After any
-- direct password change, re-apply with --force-password to set the .env value again.
\if :set_pipeline_agent_password
alter role pipeline_agent password :'pipeline_agent_password';
\endif
\if :set_dashboard_ro_password
alter role dashboard_ro password :'dashboard_ro_password';
\endif
alter role pipeline_agent connection limit 20;
alter role dashboard_ro   connection limit 10;
alter role dashboard_ro set default_transaction_read_only = on;
alter role pipeline_agent set search_path = pipeline, content, extensions, public;
alter role dashboard_ro   set search_path = pipeline, content, extensions, public;
alter role pipeline_agent set statement_timeout = '60s';
alter role dashboard_ro   set statement_timeout = '30s';

grant usage on schema pipeline, content, extensions to pipeline_agent, dashboard_ro;

-- pipeline_agent
grant select, insert, update, delete on pipeline.runs, pipeline.tasks, pipeline.evidence,
  pipeline.launch_channels, pipeline.sync_issues to pipeline_agent;
grant select, insert, update, delete on content.narratives, content.hooks, content.stories to pipeline_agent;
grant select, insert on content.story_use to pipeline_agent;
grant select, insert, update on content.engagement, content.posts to pipeline_agent;
grant select on content.engagement_events, content.post_events to pipeline_agent;
grant select on all tables in schema pipeline, content to pipeline_agent;   -- views
grant usage on all sequences in schema pipeline, content to pipeline_agent;
grant execute on all functions in schema pipeline, content to pipeline_agent;

-- dashboard_ro
grant select on all tables in schema pipeline, content to dashboard_ro;
grant execute on function content.search(text, extensions.vector, int, text),
  content.link_key(text), content.clean_link(text), content.status_rank(text), pipeline.is_ref(text)
  to dashboard_ro;

-- RLS: one permissive policy per role and table (single-owner today; the
-- owner column is kept for per-client policies later).
do $$
declare t record;
begin
  for t in select schemaname, tablename from pg_tables where schemaname in ('pipeline','content') loop
    execute format('drop policy if exists pipeline_agent_all on %I.%I', t.schemaname, t.tablename);
    execute format('create policy pipeline_agent_all on %I.%I for all to pipeline_agent using (true) with check (true)',
                   t.schemaname, t.tablename);
    execute format('drop policy if exists dashboard_ro_read on %I.%I', t.schemaname, t.tablename);
    execute format('create policy dashboard_ro_read on %I.%I for select to dashboard_ro using (true)',
                   t.schemaname, t.tablename);
  end loop;
end $$;
