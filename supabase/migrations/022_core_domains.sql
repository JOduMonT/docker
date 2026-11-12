-- 022_core_domains.sql  (apply as postgres, the apply.py default)
-- Jon 2026-11-12: one shared domain list that links books, research, pipeline, courses and content.
-- core.domains: 30 broad parents (level 1, Jon-approved list incl. copilot-m365) and the fine slugs
-- (level 2) used anywhere. core.domain_rules files a slug under a parent (first matching rule by
-- priority; editable, so a wrong placement is fixed by editing a rule or the slug's parent_slug).
-- Writers are untouched: each area keeps its free-text domain column; a domain_slug link column
-- beside it is filled by trigger, and an unknown slug is auto-created (rule parent, else 'unsorted').
-- NocoDB renders Links only within a schema, so each area also gets a view with the parent name.
-- 'Never raises' holds for writers with USAGE core + INSERT core.domains (today: pipeline_agent, which
-- writes books, research, runs, stories and taxonomy). A new writer role needs the same two grants.
-- Writers may insert level-2 slugs only in practice; top-level parents are added by migration.

create schema if not exists core;

create table if not exists core.domains (
  slug        text primary key,
  name        text,
  description text,
  parent_slug text references core.domains (slug),
  level       smallint not null default 2 check (level in (1, 2)),
  created_at  timestamptz not null default now(),
  constraint domains_parent_level check ((level = 1) = (parent_slug is null))
);
create table if not exists core.domain_rules (
  priority    int primary key,
  parent_slug text not null references core.domains (slug),
  pattern     text not null           -- Postgres regex on the child slug
);
insert into core.domains (slug, name, level) values
  ('copilot-m365', 'Microsoft Copilot & M365', 1),
  ('ai-automation', 'AI & Automation', 1),
  ('security-privacy', 'Security, Privacy & Compliance', 1),
  ('data-analytics', 'Data & Analytics', 1),
  ('software-it', 'Software, Cloud & IT', 1),
  ('therapy-mental-health', 'Therapy, Hypnosis & Mental Health', 1),
  ('psychology', 'Psychology & Behaviour', 1),
  ('coaching', 'Coaching & Facilitation', 1),
  ('learning-education', 'Learning, Teaching & Training', 1),
  ('career-work', 'Career & Professional Development', 1),
  ('marketing-sales', 'Marketing, Sales & Branding', 1),
  ('content-communication', 'Writing, Content & Communication', 1),
  ('entrepreneurship', 'Entrepreneurship & Small Business', 1),
  ('leadership-org', 'Leadership & Organizations', 1),
  ('business-strategy', 'Business Strategy & Operations', 1),
  ('finance-economics', 'Finance, Money & Economics', 1),
  ('personal-development', 'Personal Development & Productivity', 1),
  ('health-fitness', 'Health, Fitness & Nutrition', 1),
  ('spirituality-religion', 'Spirituality, Religion & Esoterica', 1),
  ('philosophy-thinking', 'Philosophy & Critical Thinking', 1),
  ('politics-society', 'Politics, Law & Society', 1),
  ('history-culture', 'History & Culture', 1),
  ('fiction-literature', 'Fiction & Literature', 1),
  ('science-math', 'Science & Mathematics', 1),
  ('engineering-making', 'Engineering, Trades & Making', 1),
  ('arts-design', 'Arts, Design & Media', 1),
  ('family-relationships', 'Family, Parenting & Relationships', 1),
  ('lifestyle-home', 'Lifestyle, Food & Home', 1),
  ('reference-general', 'Reference & General', 1),
  ('unsorted', 'Unsorted (new or unmatched slugs)', 1)
on conflict (slug) do nothing;

insert into core.domain_rules (priority, parent_slug, pattern) values
  (1, 'philosophy-thinking', '^decision\-science$'),
  (2, 'personal-development', '^time\-management$'),
  (3, 'therapy-mental-health', 'neuro-?linguistic|(stress|anger|trauma)-management'),
  (4, 'health-fitness', '(pain|weight|diabetes|sleep)-management'),
  (5, 'career-work', 'networking'),
  (6, 'security-privacy', 'ransomware|malware|threat-intel'),
  (100, 'copilot-m365', '(copilot|microsoft|m365|office-?365|sharepoint|onedrive|power-platform|power-automate|power-?apps|power-bi|(^|-)excel(-|$)|outlook|purview|(^|-)viva(-|$)|dynamics-365)'),
  (110, 'ai-automation', '(^ai-|-ai$|-ai-|artificial-intel|machine-learn|deep-learn|llm|prompt|agent|generative|chatbot|automation|copilot|neural-net|(^|-)nlp(-|$))'),
  (120, 'security-privacy', '(secur|privacy|cyber|compliance|risk-man|forensic|hacking|cryptograph|confidential|identity-)'),
  (130, 'data-analytics', '(data-|-data$|analytics|statistic|business-intel|database|visualization)'),
  (140, 'software-it', '(software|program|coding|devops|cloud|infrastructure|site-reliab|(^|-)it(-|$)|sysadmin|network-(eng|sec|admin)|computer-network|linux|kubernetes|web-dev|systems-|computer-sci|computing|open-standard|platform-eng|(^|-)apis?(-|$))'),
  (150, 'therapy-mental-health', '(therap|hypno|clinical|mental-health|psychiatr|trauma|counsel|addiction|anxiety|depress|neurolinguistic|nlp-|somatic|mindfulness)'),
  (160, 'psychology', '(psycholog|behavio|cognitive|neuroscien|persuasion|influence|emotion)'),
  (170, 'coaching', '(coach|facilitat|mentor)'),
  (180, 'learning-education', '(educat|teach|learning|training|instruction|pedagog|curricul|study-skill|language-learn|literacy)'),
  (190, 'career-work', '(career|job-|resume|interview|professional-dev|workplace|remote-work|freelanc)'),
  (200, 'marketing-sales', '(market|sales|brand|advertis|seo|copywrit|social-media|growth|customer|positioning|prospect|reputation|public-relation|influencer)'),
  (210, 'content-communication', '(writ|content|communicat|storytell|public-speak|rhetoric|journal|media-literacy|presentation|negotiat|publishing|quotation)'),
  (220, 'entrepreneurship', '(entrepreneur|startup|small-bus|side-hustle|bootstrap|solopreneur|consult|business-model|fundrais|nonprofit|local-market)'),
  (230, 'leadership-org', '(leader|organi[sz]ation|team|culture|change-man|hr-|human-resource|talent|governance|management-leadership)'),
  (240, 'business-strategy', '(strateg|management|business|operation|project|product-man|lean|agile|innovation|decision|service-man|itil|process|supply-chain|quality)'),
  (250, 'finance-economics', '(financ|invest|trading|econom|money|accounting|wealth|crypto|real-estate|(^|-)tax(es|ation)?(-|$)|retirement|banking)'),
  (260, 'personal-development', '(personal-dev|self-|productiv|habit|motivation|success|time-man|life-|goal|happiness|wellbeing|well-being|resilience|confidence|minimalism)'),
  (270, 'health-fitness', '(health|fitness|nutrition|diet|exercise|medic|sleep|yoga|anatomy|physiolog|longevity|herbal|aging|sport|martial)'),
  (280, 'spirituality-religion', '(spirit|religio|theolog|bibl|meditat|esoter|occult|mystic|buddh|christian|islam|tarot|astrolog|kundalini|tantra|shaman|energy-heal|magic|paranormal|conspiracy|alternative-hist|new-age)'),
  (290, 'philosophy-thinking', '(philosoph|ethic|logic|critical-think|stoic|reasoning|epistem|mental-model|systems-think)'),
  (300, 'politics-society', '(politic|(^|-)laws?(-|$)|legal|policy|sociolog|society|social-|civic|geopolit|government|activism|gender|(^|-)race(-|$)|digital-citizen|public-)'),
  (310, 'history-culture', '(histor|cultur|anthropolog|archaeolog|biograph|memoir|military|(^|-)wars?(-|$)|warfare|wartime)'),
  (320, 'fiction-literature', '(fiction|literat|novel|poetry|fantasy|thriller|mystery|romance|horror|classic|short-stor|drama|comic|manga|children)'),
  (330, 'science-math', '(scien|physic|chemist|biolog|math|astronom|ecolog|geolog|evolution|quantum|environment|climate)'),
  (340, 'engineering-making', '(engineer|electr|mechanic|maker|diy|woodwork|craft|robot|hardware|3d-|construct|automotive|repair)'),
  (350, 'arts-design', '((^|-)arts?(-|$)|design|music|photograph|film|video|graphic|architect|creativ|(^|-)games?(-|$)|gaming|animation|drawing)'),
  (360, 'family-relationships', '(famil|parent|relationship|marriage|dating|(^|-)sex(ual|uality)?(-|$)|child|friendship|(^|-)love(-|$))'),
  (370, 'lifestyle-home', '(culinar|cook|food|home|garden|travel|lifestyle|fashion|(^|-)pets?(-|$)|outdoor|survival)'),
  (380, 'reference-general', '(reference|general|dictionar|encyclop|trivia|miscellan)')
on conflict (priority) do nothing;

-- Parent for a slug: the first rule that matches, else 'unsorted'.
create or replace function core.parent_for(p_slug text) returns text
  language sql stable set search_path = core, pg_temp as $$
  select coalesce((select parent_slug from core.domain_rules where p_slug ~ pattern order by priority limit 1), 'unsorted')
$$;

-- Normalise a free-text domain to a slug and make sure it exists; NULL for blank. Never raises.
create or replace function core.ensure_domain(p_value text) returns text
  language plpgsql set search_path = core, pg_temp as $$
declare s text := nullif(regexp_replace(lower(trim(coalesce(p_value, ''))), '\s+', '-', 'g'), '');
begin
  if s is not null and not exists (select 1 from core.domains where slug = s) then
    insert into core.domains (slug, name, parent_slug, level)
      values (s, initcap(replace(s, '-', ' ')), core.parent_for(s), 2) on conflict do nothing;
  end if;
  return s;
end $$;

-- Seed the fine slugs in use (a slug equal to a parent slug stays the parent).
insert into core.domains (slug, name, description, parent_slug, level)
  select t.slug, initcap(replace(t.slug, '-', ' ')), t.description, core.parent_for(t.slug), 2
  from books.taxonomy t where nullif(trim(t.slug), '') is not null
  on conflict (slug) do nothing;
insert into core.domains (slug, name, parent_slug, level)
  select distinct s, initcap(replace(s, '-', ' ')), core.parent_for(s), 2
  from (select lower(trim(domain)) s from books.triage
        union select lower(trim(domain)) from research.triage
        union select lower(trim(domain)) from pipeline.runs) x
  where nullif(s, '') is not null
  on conflict (slug) do nothing;

-- Link columns beside the free-text domain + the fill trigger.
create or replace function core.fill_domain_slug() returns trigger
  language plpgsql set search_path = core, pg_temp as $$
begin
  new.domain_slug := core.ensure_domain(new.domain);
  return new;
end $$;

alter table books.triage    add column if not exists domain_slug text references core.domains (slug);
alter table research.triage add column if not exists domain_slug text references core.domains (slug);
alter table pipeline.runs   add column if not exists domain_slug text references core.domains (slug);
update books.triage    set domain_slug = core.ensure_domain(domain) where domain_slug is null;
update research.triage set domain_slug = core.ensure_domain(domain) where domain_slug is null;
update pipeline.runs   set domain_slug = core.ensure_domain(domain) where domain_slug is null;
drop trigger if exists triage_domain_slug on books.triage;
create trigger triage_domain_slug before insert or update of domain on books.triage
  for each row execute function core.fill_domain_slug();
drop trigger if exists triage_domain_slug on research.triage;
create trigger triage_domain_slug before insert or update of domain on research.triage
  for each row execute function core.fill_domain_slug();
drop trigger if exists runs_domain_slug on pipeline.runs;
create trigger runs_domain_slug before insert or update of domain on pipeline.runs
  for each row execute function core.fill_domain_slug();

-- books.taxonomy is the books' own slug list: a new taxonomy slug also becomes a domain.
create or replace function core.taxonomy_domain() returns trigger
  language plpgsql set search_path = core, pg_temp as $$
begin perform core.ensure_domain(new.slug); return new; end $$;
drop trigger if exists taxonomy_domain on books.taxonomy;
create trigger taxonomy_domain before insert or update of slug on books.taxonomy
  for each row execute function core.taxonomy_domain();

-- Courses <-> domains (seeded from the course titles; reviewed list in the PR / report).
create table if not exists courses.catalog_domains (
  course_id   text not null references courses.catalog (legacy_id) on delete cascade,
  domain_slug text not null references core.domains (slug),
  primary key (course_id, domain_slug)
);
insert into courses.catalog_domains (course_id, domain_slug) values
  ('1','philosophy-thinking'), ('1','ai-automation'),
  ('2','ai-automation'), ('2','learning-education'),
  ('3','copilot-m365'), ('3','ai-automation'),
  ('4','copilot-m365'),
  ('5','copilot-m365'),
  ('6','ai-automation'), ('6','data-analytics'), ('6','copilot-m365'),
  ('7','copilot-m365'), ('7','ai-automation'),
  ('8','security-privacy'), ('8','ai-automation'), ('8','copilot-m365'),
  ('9','copilot-m365'), ('9','leadership-org'),
  ('10','copilot-m365'), ('10','leadership-org'),
  ('11','security-privacy'), ('11','leadership-org'), ('11','ai-automation'),
  ('12','security-privacy'),
  ('13','copilot-m365'), ('13','philosophy-thinking'), ('13','ai-automation'),
  ('14','ai-automation'), ('14','copilot-m365'),
  ('15','ai-automation'), ('15','philosophy-thinking'),
  ('16','security-privacy'), ('16','ai-automation')
  on conflict do nothing;

-- Stories <-> domains, from the comma list in content.stories.themes (kept in sync by trigger).
create table if not exists content.story_domains (
  story_id    text not null references content.stories (story_id) on delete cascade,
  domain_slug text not null references core.domains (slug),
  primary key (story_id, domain_slug)
);
create or replace function content.story_domains_sync() returns trigger
  language plpgsql set search_path = content, core, pg_temp as $$
begin
  delete from content.story_domains where story_id = new.story_id;
  insert into content.story_domains (story_id, domain_slug)
    select distinct new.story_id, core.ensure_domain(t)
    from unnest(string_to_array(coalesce(new.themes, ''), ',')) t
    where core.ensure_domain(t) is not null
    on conflict do nothing;
  return null;
end $$;
drop trigger if exists stories_domains on content.stories;
create trigger stories_domains after insert or update of themes on content.stories
  for each row execute function content.story_domains_sync();
insert into content.story_domains (story_id, domain_slug)
  select distinct s.story_id, core.ensure_domain(t)
  from content.stories s, unnest(string_to_array(coalesce(s.themes, ''), ',')) t
  where core.ensure_domain(t) is not null
  on conflict do nothing;

-- Engagement topics are free phrases: a link table, seeded by hand, filled by agents later.
create table if not exists content.engagement_domains (
  engagement_id text not null references content.engagement (engagement_id) on delete cascade,
  domain_slug   text not null references core.domains (slug),
  primary key (engagement_id, domain_slug)
);
insert into content.engagement_domains (engagement_id, domain_slug)
  select e.engagement_id, d from content.engagement e,
    lateral (values
      (case when e.topic ilike '%shadow ai%' then 'security-privacy' end),
      (case when e.topic ilike '%responsible ai%' then 'security-privacy' end),
      (case when e.topic ilike '%ai%' then 'ai-automation' end),
      (case when e.topic ilike '%learning%' then 'learning-education' end)) v(d)
  where d is not null
  on conflict do nothing;

-- Per-area views with the parent name (NocoDB shows these; it cannot render cross-schema Links).
create or replace view books.v_triage_domains with (security_invoker = true) as
  select t.id, t.filename, t.book_id, t.domain, t.domain_slug, d.parent_slug, p.name as parent_name
  from books.triage t left join core.domains d on d.slug = t.domain_slug left join core.domains p on p.slug = d.parent_slug;
create or replace view research.v_triage_domains with (security_invoker = true) as
  select t.id, t.item, t.domain, t.domain_slug, d.parent_slug, p.name as parent_name
  from research.triage t left join core.domains d on d.slug = t.domain_slug left join core.domains p on p.slug = d.parent_slug;
create or replace view pipeline.v_runs_domains with (security_invoker = true) as
  select r.run_id, r.domain, r.domain_slug, d.parent_slug, p.name as parent_name
  from pipeline.runs r left join core.domains d on d.slug = r.domain_slug left join core.domains p on p.slug = d.parent_slug;
create or replace view courses.v_catalog_domains with (security_invoker = true) as
  select c.legacy_id as course_id, c.course, cd.domain_slug, coalesce(d.parent_slug, d.slug) as parent_slug,
         coalesce(p.name, d.name) as parent_name
  from courses.catalog c join courses.catalog_domains cd on cd.course_id = c.legacy_id
  join core.domains d on d.slug = cd.domain_slug left join core.domains p on p.slug = d.parent_slug;
create or replace view content.v_story_domains with (security_invoker = true) as
  select s.story_id, s.title, sd.domain_slug, coalesce(d.parent_slug, d.slug) as parent_slug, coalesce(p.name, d.name) as parent_name
  from content.stories s join content.story_domains sd on sd.story_id = s.story_id
  join core.domains d on d.slug = sd.domain_slug left join core.domains p on p.slug = d.parent_slug;

-- Grants and RLS (pattern of 010/015: one writer policy, one read policy).
grant usage on schema core to pipeline_agent, ops_app, dashboard_ro, nocodb_ro;   -- ops_app: people_agents (023)
grant select, insert on core.domains to pipeline_agent;   -- writers that auto-create slugs (ensure_domain needs USAGE core + INSERT here)
grant select on core.domains, core.domain_rules to dashboard_ro, nocodb_ro, pipeline_agent, ops_app;
grant execute on function core.parent_for(text), core.ensure_domain(text) to pipeline_agent;
grant select, insert, delete on courses.catalog_domains, content.story_domains, content.engagement_domains to pipeline_agent;
grant select on courses.catalog_domains, content.story_domains, content.engagement_domains to nocodb_ro;
grant select on content.story_domains, content.engagement_domains, content.v_story_domains, pipeline.v_runs_domains to dashboard_ro;
grant select on books.v_triage_domains, research.v_triage_domains, pipeline.v_runs_domains,
  courses.v_catalog_domains, content.v_story_domains to nocodb_ro, pipeline_agent;
do $$
declare t text;
begin
  foreach t in array array['core.domains','core.domain_rules','courses.catalog_domains','content.story_domains','content.engagement_domains'] loop
    execute format('alter table %s enable row level security', t);
    execute format('drop policy if exists pipeline_agent_write on %s', t);
    execute format('create policy pipeline_agent_write on %s for all to pipeline_agent using (true) with check (true)', t);
    execute format('drop policy if exists read_only on %s', t);
    execute format('create policy read_only on %s for select to nocodb_ro, dashboard_ro using (true)', t);
  end loop;
end $$;