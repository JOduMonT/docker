-- 003: product pipeline + content (CMS) in Supabase. Replaces the pipeline-api
-- container (SQLite, JSONL logs, Excel). Idempotent: safe to re-run.
--
--   pipeline.*  runs and their gate data. Source of truth: run folders
--               (run.json), upserted by the sync script (pipeline_db.py sync).
--   content.*   narratives, hooks, stories: upserted from wiki/brand markdown
--               and 04b-narrative.md by the same sync.
--               engagement (LinkedIn comments), posts (Jon's own posts),
--               story_use: written directly by agents (no files).
--
-- Rules live here as constraints and triggers, not in app code. Every change
-- to engagement and posts is logged (*_events), like ops.task_events.
--
-- Search: tsvector (full text) + pgvector (semantic), hybrid via
-- content.search(). Embeddings: sentence-transformers/
-- paraphrase-multilingual-MiniLM-L12-v2, 384 dimensions, computed locally
-- (fastembed, ONNX) by pipeline_db.py; NULL until computed.

create schema if not exists extensions;
create extension if not exists vector with schema extensions;

create schema if not exists pipeline;
create schema if not exists content;

-- ------------------------------------------------------------------ helpers

-- Lowercase slug, used for run ids, post ids, story/hook refs.
create or replace function pipeline.is_ref(v text) returns boolean
  language sql immutable as $$ select v ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' $$;

-- One key per LinkedIn post, whatever the URL shape: activity / share /
-- ugcPost ids (urn:li:<type>:N or /posts/<slug>-<type>-N), else host without
-- www + path without query, fragment, '//', '/./' or trailing slash.
create or replace function content.link_key(link text) returns text
  language plpgsql immutable as $$
declare
  p text := regexp_replace(lower(split_part(split_part(link, '#', 1), '?', 1)), '^https?://', '');
  m text[];
begin
  p := replace(p, '%2f', '/');
  p := regexp_replace(regexp_replace(p, '/{2,}', '/', 'g'), '/(\./)+', '/', 'g');
  m := regexp_match(p, '^[^/]+(/embed)?/feed/update/urn:li:(activity|share|ugcpost):(\d{10,25})/?$');
  if m is not null then return m[2] || ':' || m[3]; end if;
  m := regexp_match(p, '^[^/]+/posts/[^/]*[_-](activity|share|ugcpost)-(\d{10,25})');
  if m is not null then return m[1] || ':' || m[2]; end if;
  p := regexp_replace(p, '^www\.', '');
  return rtrim(p, '/');
end $$;

-- Shown link: scheme kept (the column checks reject anything but https), lowercase
-- host, no query, fragment or trailing slash.
create or replace function content.clean_link(link text) returns text
  language plpgsql immutable as $$
declare
  m text[] := regexp_match(split_part(split_part(trim(link), '#', 1), '?', 1), '^(https?)://([^/]+)(.*)$');
begin
  if m is null then return trim(link); end if;          -- the column check rejects it
  return rtrim(lower(m[1]) || '://' || lower(m[2]) || m[3], '/');
end $$;

-- --------------------------------------------------------------- pipeline

create table if not exists pipeline.runs (
  run_id            text primary key check (pipeline.is_ref(run_id)),
  owner             text not null default 'client0',
  requester         text,
  source_type       text check (source_type in ('file','url','text')),
  source_ref        text,
  source_hash       text check (source_hash ~ '^sha256:[0-9a-f]{64}$'),
  created_at        timestamptz,
  gate              smallint not null check (gate between 0 and 7),
  state             text not null check (state in ('running','passed','failed','no-go','sent-back')),
  reason            text,
  verdict           text check (verdict in ('go','no-go')),
  framing           text check (framing in ('literal','job','shifted')),
  domain            text check (domain ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  domain_is_new     boolean,
  thesis            text,
  core_context      text,
  mvp_form          text,
  mvp_build_days    smallint check (mvp_build_days between 1 and 14),
  delivery_mode     text check (delivery_mode in ('self-serve','handover')),
  feedback_question text,
  run_json          jsonb not null,               -- the file as synced, for audit
  synced_at         timestamptz not null default now()
);
create index if not exists runs_source_hash on pipeline.runs (owner, source_hash);

create table if not exists pipeline.tasks (
  run_id      text not null references pipeline.runs(run_id) on delete cascade,
  task_id     text not null,
  name        text not null,
  frequency   smallint not null check (frequency between 1 and 5),
  time        smallint not null check (time between 1 and 5),
  error_risk  smallint not null check (error_risk between 1 and 5),
  ai_fit      smallint not null check (ai_fit between 1 and 5),
  sensitivity smallint not null check (sensitivity between 1 and 5),
  priority    smallint not null,
  primary key (run_id, task_id),
  constraint priority_is_formula
    check (priority = frequency + time + error_risk + ai_fit - sensitivity)
);

create table if not exists pipeline.evidence (
  id                bigint generated always as identity primary key,
  run_id            text not null references pipeline.runs(run_id) on delete cascade,
  idx               smallint not null,
  claim             text not null,
  url               text not null,
  quote             text not null,
  retrieved_at      text,
  type              text not null check (type in ('pain','pay','opinion')),
  competitor_source boolean not null,
  fts               tsvector generated always as
                      (to_tsvector('english', coalesce(claim,'') || ' ' || coalesce(quote,''))) stored,
  embedding         extensions.vector(384),
  unique (run_id, idx)
);

create table if not exists pipeline.launch_channels (
  run_id       text not null references pipeline.runs(run_id) on delete cascade,
  idx          smallint not null,
  name         text not null,
  url          text not null,
  own_page     boolean not null,
  reach        integer check (reach >= 0),
  first_action text not null,
  primary key (run_id, idx)
);

-- Files the last sync could not load (shown on the dashboard; replaced each sync).
create table if not exists pipeline.sync_issues (
  source   text not null,
  level    text not null check (level in ('rejected','warning','skipped')),
  message  text not null,
  seen_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------- content

create table if not exists content.narratives (
  narrative_id   text primary key check (narrative_id ~ '^(run|offer):'),
  owner          text not null default 'client0',
  kind           text not null check (kind in ('run','offer')),
  run_id         text,
  offer          text,
  source_path    text not null,
  one_line_story text,
  core_message   text,
  proof_point    text,
  cta            text,
  fts            tsvector generated always as (to_tsvector('english',
                   coalesce(one_line_story,'') || ' ' || coalesce(core_message,'') || ' ' ||
                   coalesce(proof_point,'') || ' ' || coalesce(offer,''))) stored,
  embedding      extensions.vector(384)
);

create table if not exists content.hooks (
  narrative_id text not null references content.narratives(narrative_id) on delete cascade,
  idx          smallint not null,
  hook_id      text not null check (hook_id ~ '^h-[0-9a-f]{12}$'),
  quote        text not null,
  url          text,
  votes        bigint check (votes between 0 and 1000000000000),
  source_file  text,
  fts          tsvector generated always as (to_tsvector('english', quote)) stored,
  embedding    extensions.vector(384),
  primary key (narrative_id, idx)
);
create index if not exists hooks_hook_id on content.hooks (hook_id);

create table if not exists content.stories (
  story_id    text primary key check (pipeline.is_ref(story_id)),
  owner       text not null default 'client0',
  title       text not null,
  offers      text,
  themes      text,
  public_use  text,
  body        text,
  source_path text not null,
  fts         tsvector generated always as (to_tsvector('english',
                coalesce(title,'') || ' ' || coalesce(body,'') || ' ' ||
                coalesce(offers,'') || ' ' || coalesce(themes,''))) stored,
  embedding   extensions.vector(384)
);

-- One row per use of a story or hook. Append-only for agents (no update/delete
-- grant). The ref must exist when the use is logged.
create table if not exists content.story_use (
  id         bigint generated always as identity primary key,
  use_uid    uuid not null unique default gen_random_uuid(),   -- send your own to make retries safe
  owner      text not null default 'client0',
  kind       text not null check (kind in ('story','hook')),
  ref_id     text not null,
  asset_path text not null check (length(asset_path) between 1 and 500),
  channel    text not null check (length(channel) between 1 and 100),
  used_at    timestamptz not null default now(),
  logged_at  timestamptz not null default now(),
  logged_by  text not null default current_user
);
create index if not exists story_use_ref on content.story_use (owner, kind, ref_id);

create or replace function content.story_use_check_ref() returns trigger language plpgsql as $$
begin
  if new.kind = 'story' and not exists
       (select 1 from content.stories s where s.story_id = new.ref_id and s.owner = new.owner) then
    raise exception 'no story % for owner %', new.ref_id, new.owner using errcode = 'foreign_key_violation';
  elsif new.kind = 'hook' and not exists
       (select 1 from content.hooks h join content.narratives n using (narrative_id)
         where h.hook_id = new.ref_id and n.owner = new.owner) then
    raise exception 'no hook % for owner %', new.ref_id, new.owner using errcode = 'foreign_key_violation';
  end if;
  new.logged_at := now();
  new.logged_by := current_user;
  return new;
end $$;
drop trigger if exists story_use_check_ref on content.story_use;
create trigger story_use_check_ref before insert on content.story_use
  for each row execute function content.story_use_check_ref();

-- True when two row images differ at most in embedding/fts/updated_at.
-- Who made a change: the agent name pipeline_db.py sets for the session
-- (set_config('pipeline.agent', …)), then the database role.
-- It is a label the caller sets, not an identity: never proof of approval.
-- Names of people (the operator) are shown as a claim.
create or replace function content.actor() returns text language sql stable as $$
  select case
    when nullif(trim(current_setting('pipeline.agent', true)), '') is null then session_user::text
    when lower(trim(current_setting('pipeline.agent', true))) ~ '^(jon|jonathan|jonathan dumont|jodumont|operator|owner|client0)$'
      then 'claimed "' || trim(current_setting('pipeline.agent', true)) || '" (' || session_user || ')'
    else trim(current_setting('pipeline.agent', true)) || ' (' || session_user || ')'
  end
$$;

create or replace function content.same_but_embedding(a jsonb, b jsonb) returns boolean
  language sql immutable as $$
  select (a - 'embedding' - 'fts' - 'updated_at') = (b - 'embedding' - 'fts' - 'updated_at')
$$;

-- LinkedIn comments: one row per post (engagement_id from the link key).
-- New draft for the same post: insert ... on conflict (engagement_id) do update.
create table if not exists content.engagement (
  engagement_id    text primary key,
  owner            text not null default 'client0',
  link             text not null check (link ~ '^https://([a-z0-9-]+\.)*linkedin\.com/\S+$'),
  drafted_at       timestamptz not null default now(),
  author           text not null check (length(author) between 1 and 200),
  author_role      text,
  topic            text,
  search_query     text,
  comment_text     text not null check (length(comment_text) between 1 and 5000),
  claim_used       text,
  hook_or_story_id text check (pipeline.is_ref(hook_or_story_id)),
  posted           boolean not null default false,
  replies          integer check (replies >= 0),
  reactions        integer check (reactions >= 0),
  last_update      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  fts              tsvector generated always as (to_tsvector('english',
                     comment_text || ' ' || coalesce(topic,''))) stored,
  embedding        extensions.vector(384)
);

create table if not exists content.engagement_events (
  id            bigint generated always as identity primary key,
  engagement_id text not null,
  at            timestamptz not null default now(),
  op            text not null,
  changed_by    text not null default current_user,
  snapshot      jsonb not null
);

create or replace function content.engagement_before() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and content.same_but_embedding(to_jsonb(new), to_jsonb(old)) then
    new.updated_at := old.updated_at; -- only the embedding was filled in; no forged timestamps
    return new;
  end if;
  new.link := content.clean_link(new.link);
  new.engagement_id := 'e-' || left(encode(sha256(convert_to(content.link_key(new.link), 'UTF8')), 'hex'), 12);
  if tg_op = 'UPDATE' then
    if new.engagement_id <> old.engagement_id then
      raise exception 'link points to another post (% -> %); insert a new row instead',
        old.engagement_id, new.engagement_id;
    end if;
    -- a new embedding is needed when the text changes
    if new.comment_text is distinct from old.comment_text or new.topic is distinct from old.topic then
      new.embedding := null;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

-- SECURITY DEFINER: agents may not write the event log directly.
create or replace function content.engagement_log() returns trigger language plpgsql
  security definer set search_path = content, pg_temp as $$
begin
  if tg_op = 'UPDATE' and content.same_but_embedding(to_jsonb(new), to_jsonb(old)) then
    return new;
  end if;
  insert into content.engagement_events (engagement_id, op, changed_by, snapshot)
  values (new.engagement_id, lower(tg_op), content.actor(), to_jsonb(new) - 'embedding' - 'fts');
  return new;
end $$;

drop trigger if exists engagement_before on content.engagement;
create trigger engagement_before before insert or update on content.engagement
  for each row execute function content.engagement_before();
drop trigger if exists engagement_log on content.engagement;
create trigger engagement_log after insert or update on content.engagement
  for each row execute function content.engagement_log();

-- Jon's own posts (CMS / editorial calendar). Status moves only forward;
-- approval is write-once; nothing reaches approved without approved_at.
-- Status is a record written by the agent, not a permission check: Jon's
-- explicit yes per post stays the rule in the routine.
create table if not exists content.posts (
  post_id      text primary key check (post_id ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  owner        text not null default 'client0',
  campaign     text,
  offer        text,
  platform     text not null check (platform in ('linkedin','facebook','bluesky','mastodon','website')),
  format       text not null check (format in ('carousel-pdf','image','text','video','link')),
  planned_date date,
  status       text not null default 'drafted'
               check (status in ('drafted','approved','posted','verified','skipped')),
  text         text not null check (length(text) between 1 and 15000),
  asset        text,
  alt_text     text,
  narrative    text,
  link         text check (link ~ '^https://\S+$'),
  approved_at  timestamptz,
  approval_ref text,
  posted_at    timestamptz,
  replies      integer check (replies >= 0),
  reactions    integer check (reactions >= 0),
  last_update  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  fts          tsvector generated always as (to_tsvector('english',
                 text || ' ' || coalesce(campaign,'') || ' ' || coalesce(offer,''))) stored,
  embedding    extensions.vector(384),
  constraint approved_needs_approved_at
    check (status not in ('approved','posted','verified') or approved_at is not null),
  constraint approved_needs_approval_ref
    check (status not in ('approved','posted','verified') or coalesce(trim(approval_ref), '') <> ''),
  constraint posted_needs_posted_at
    check (status not in ('posted','verified') or posted_at is not null),
  constraint posted_not_before_approved
    check (posted_at is null or approved_at is null or posted_at::date >= approved_at::date)
);
create index if not exists posts_calendar on content.posts (planned_date, post_id);
do $$ begin   -- existing tables (003 re-run): add the constraint added after first apply
  if not exists (select 1 from pg_constraint where conname = 'approved_needs_approval_ref'
                 and conrelid = 'content.posts'::regclass) then
    alter table content.posts add constraint approved_needs_approval_ref
      check (status not in ('approved','posted','verified') or coalesce(trim(approval_ref), '') <> '');
  end if;
end $$;

create table if not exists content.post_events (
  id         bigint generated always as identity primary key,
  post_id    text not null,
  at         timestamptz not null default now(),
  op         text not null,
  old_status text,
  new_status text,
  changed_by text not null default current_user,
  snapshot   jsonb not null
);

create or replace function content.status_rank(s text) returns int language sql immutable as $$
  select case s when 'drafted' then 0 when 'approved' then 1 when 'posted' then 2 when 'verified' then 3 end
$$;

create or replace function content.posts_before() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and content.same_but_embedding(to_jsonb(new), to_jsonb(old)) then
    new.updated_at := old.updated_at; -- only the embedding was filled in; no forged timestamps
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'drafted' or new.approved_at is not null or new.approval_ref is not null
       or new.posted_at is not null or new.link is not null then
      raise exception 'a post starts as drafted with no approval, posted_at or link; record each step with an update';
    end if;
    new.created_at := now();
  end if;
  if tg_op = 'UPDATE' then
    if new.created_at is distinct from old.created_at then
      raise exception 'created_at never changes';
    end if;
    if old.status <> 'drafted' and (
         new.text is distinct from old.text or new.asset is distinct from old.asset
      or new.alt_text is distinct from old.alt_text or new.platform is distinct from old.platform
      or new.format is distinct from old.format or new.campaign is distinct from old.campaign
      or new.offer is distinct from old.offer or new.narrative is distinct from old.narrative) then
      raise exception 'post % is %: its content is frozen (Jon approved this exact text); create a new post instead',
        old.post_id, old.status;
    end if;
    if new.link is distinct from old.link and (old.link is not null or new.status not in ('posted','verified')) then
      raise exception 'link is set once, when the post is marked posted';
    end if;
    if old.approved_at is null and new.approved_at is not null
       and (new.approved_at < date_trunc('day', old.created_at) or new.approved_at > now() + interval '5 minutes') then
      raise exception 'approved_at must be between the post''s creation and now';
    end if;
    if old.posted_at is null and new.posted_at is not null and new.posted_at > now() + interval '5 minutes' then
      raise exception 'posted_at cannot be in the future';
    end if;
    if new.post_id <> old.post_id then
      raise exception 'post_id never changes (insert a new post instead)';
    end if;
    if new.status <> old.status then
      if old.status in ('skipped','verified') then
        raise exception 'status % is final; cannot become %', old.status, new.status;
      elsif new.status = 'skipped' and old.status = 'posted' then
        raise exception 'a posted post cannot become skipped';
      elsif new.status <> 'skipped' and content.status_rank(new.status) < content.status_rank(old.status) then
        raise exception 'status moves only forward: % -> %', old.status, new.status;
      end if;
    end if;
    if old.approved_at is not null and new.approved_at is distinct from old.approved_at then
      raise exception 'approved_at is already set and cannot change';
    end if;
    if old.approval_ref is not null and new.approval_ref is distinct from old.approval_ref then
      raise exception 'approval_ref is already set and cannot change';
    end if;
    if new.text is distinct from old.text or new.campaign is distinct from old.campaign
       or new.offer is distinct from old.offer then
      new.embedding := null;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

create or replace function content.posts_log() returns trigger language plpgsql
  security definer set search_path = content, pg_temp as $$
begin
  if tg_op = 'UPDATE' and content.same_but_embedding(to_jsonb(new), to_jsonb(old)) then
    return new;
  end if;
  insert into content.post_events (post_id, op, old_status, new_status, changed_by, snapshot)
  values (new.post_id, lower(tg_op), case when tg_op = 'UPDATE' then old.status end, new.status,
          content.actor(), to_jsonb(new) - 'embedding' - 'fts');
  return new;
end $$;

drop trigger if exists posts_before on content.posts;
create trigger posts_before before insert or update on content.posts
  for each row execute function content.posts_before();
drop trigger if exists posts_log on content.posts;
create trigger posts_log after insert or update on content.posts
  for each row execute function content.posts_log();

-- ------------------------------------------------------------------ search

create index if not exists evidence_fts   on pipeline.evidence  using gin (fts);
create index if not exists narratives_fts on content.narratives using gin (fts);
create index if not exists hooks_fts      on content.hooks      using gin (fts);
create index if not exists stories_fts    on content.stories    using gin (fts);
create index if not exists engagement_fts on content.engagement using gin (fts);
create index if not exists posts_fts      on content.posts      using gin (fts);

create index if not exists evidence_emb   on pipeline.evidence  using hnsw (embedding extensions.vector_cosine_ops);
create index if not exists narratives_emb on content.narratives using hnsw (embedding extensions.vector_cosine_ops);
create index if not exists hooks_emb      on content.hooks      using hnsw (embedding extensions.vector_cosine_ops);
create index if not exists stories_emb    on content.stories    using hnsw (embedding extensions.vector_cosine_ops);
create index if not exists engagement_emb on content.engagement using hnsw (embedding extensions.vector_cosine_ops);
create index if not exists posts_emb      on content.posts      using hnsw (embedding extensions.vector_cosine_ops);

-- Every searchable text in one place (kind, ref_id, owner, source, text, fts, embedding).
create or replace view content.search_docs with (security_invoker = true) as
  select 'story'::text as kind, story_id as ref_id, owner, source_path as source,
         title || coalesce(' — ' || body, '') as text, fts, embedding from content.stories
  union all
  select 'hook', h.hook_id, n.owner, coalesce(h.url, n.source_path), h.quote, h.fts, h.embedding
    from content.hooks h join content.narratives n using (narrative_id)
  union all
  select 'narrative', narrative_id, owner, source_path,
         concat_ws(' ', one_line_story, core_message, proof_point), fts, embedding from content.narratives
  union all
  select 'engagement', engagement_id, owner, link, comment_text, fts, embedding from content.engagement
  union all
  select 'post', post_id, owner, coalesce(link, post_id), text, fts, embedding from content.posts
  union all
  select 'evidence', e.run_id || '#' || e.idx, r.owner, e.url, e.claim || ' — ' || e.quote, e.fts, e.embedding
    from pipeline.evidence e join pipeline.runs r using (run_id);

-- Hybrid search: reciprocal-rank fusion of full text (websearch syntax, safe
-- for any user text) and, when q_embedding is given, cosine similarity.
create or replace function content.search(q text, q_embedding extensions.vector(384) default null,
                                          match_count int default 20, for_owner text default 'client0')
returns table (kind text, ref_id text, source text, snippet text, score double precision)
language sql stable security invoker set search_path = content, extensions, pg_temp as $$
  with docs as (select * from content.search_docs where owner = for_owner),
  ft as (
    select d.kind, d.ref_id, row_number() over (order by ts_rank_cd(d.fts, query) desc) as r
    from docs d, websearch_to_tsquery('english', coalesce(q, '')) query
    where d.fts @@ query
    limit greatest(match_count, 1) * 4
  ),
  sem as (
    select d.kind, d.ref_id, row_number() over (order by d.embedding <=> q_embedding) as r
    from docs d
    where q_embedding is not null and d.embedding is not null
    order by d.embedding <=> q_embedding
    limit greatest(match_count, 1) * 4
  ),
  fused as (
    select kind, ref_id, sum(1.0 / (60 + r)) as score
    from (select * from ft union all select * from sem) x
    group by kind, ref_id
  )
  select f.kind, f.ref_id, d.source,
         ts_headline('english', d.text, websearch_to_tsquery('english', coalesce(q, '')),
                     'StartSel=[,StopSel=],MaxWords=24,MinWords=8') as snippet,
         f.score
  from fused f join docs d using (kind, ref_id)
  order by f.score desc, f.kind, f.ref_id
  limit least(greatest(match_count, 1), 100)
$$;

-- ---------------------------------------------------------- dashboard views
-- What the Excel sheets showed, for Appsmith (read by dashboard_ro).

create or replace view pipeline.v_runs with (security_invoker = true) as
  select run_id, owner, requester, source_type, source_ref, source_hash, created_at, gate, state,
         reason, verdict, framing, domain, domain_is_new, thesis, core_context, synced_at
  from pipeline.runs;

create or replace view pipeline.v_top_tasks with (security_invoker = true) as
  select t.run_id, t.task_id, t.name, t.frequency, t.time, t.error_risk, t.ai_fit, t.sensitivity,
         t.priority, r.framing, r.owner
  from pipeline.tasks t join pipeline.runs r using (run_id);

create or replace view pipeline.v_funnel with (security_invoker = true) as
  select owner, gate, state, count(*) as count from pipeline.runs group by owner, gate, state;

create or replace view pipeline.v_launch with (security_invoker = true) as
  select r.run_id, r.owner, r.mvp_form, r.mvp_build_days, r.delivery_mode, r.feedback_question,
         l.name as channel, l.url, l.own_page, l.reach, l.first_action
  from pipeline.runs r left join pipeline.launch_channels l using (run_id)
  where l.run_id is not null or r.mvp_form is not null or r.mvp_build_days is not null
     or r.delivery_mode is not null or r.feedback_question is not null;

create or replace view content.v_stories_hooks with (security_invoker = true) as
  select 'hook'::text as kind, h.hook_id as id, h.quote as text, h.url as source, n.source_path as file,
         n.offer, r.domain, null::text as public_use, h.votes, n.owner,
         (select count(*) from content.story_use u where u.owner = n.owner and u.kind = 'hook' and u.ref_id = h.hook_id) as times_used,
         (select max(used_at) from content.story_use u where u.owner = n.owner and u.kind = 'hook' and u.ref_id = h.hook_id) as last_used
  from content.hooks h join content.narratives n using (narrative_id)
  left join pipeline.runs r on r.run_id = n.run_id and r.owner = n.owner
  union all
  select 'story', s.story_id, s.title, 'story bank #' || s.story_id, s.source_path, s.offers, null, s.public_use,
         null, s.owner,
         (select count(*) from content.story_use u where u.owner = s.owner and u.kind = 'story' and u.ref_id = s.story_id),
         (select max(used_at) from content.story_use u where u.owner = s.owner and u.kind = 'story' and u.ref_id = s.story_id)
  from content.stories s;

-- Posts that reuse the same asset on the same platform (check before posting).
create or replace view content.v_post_asset_reuse with (security_invoker = true) as
  select platform, asset, array_agg(post_id order by post_id) as post_ids
  from content.posts where asset is not null and status <> 'skipped'
  group by platform, asset having count(*) > 1;

-- ------------------------------------------------------------------ access
-- Not exposed to anon/authenticated (PostgREST public roles). Agents and
-- Appsmith use pipeline_agent / dashboard_ro (grants in 004, *.sql.local).

alter table pipeline.runs            enable row level security;
alter table pipeline.tasks           enable row level security;
alter table pipeline.evidence        enable row level security;
alter table pipeline.launch_channels enable row level security;
alter table pipeline.sync_issues     enable row level security;
alter table content.narratives       enable row level security;
alter table content.hooks            enable row level security;
alter table content.stories          enable row level security;
alter table content.story_use        enable row level security;
alter table content.engagement       enable row level security;
alter table content.engagement_events enable row level security;
alter table content.posts            enable row level security;
alter table content.post_events      enable row level security;
revoke all on schema pipeline, content from anon, authenticated, public;
revoke all on all tables in schema pipeline, content from anon, authenticated, public;
revoke execute on all functions in schema pipeline, content from public;
