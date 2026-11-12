-- 020_open_list_enums.sql
-- Step 3: columns with no CHECK yet -> enums (NocoDB Single select / Kanban).
-- Lists = the distinct values in the data on 2026-11-12, plus the obvious missing ones:
--   courses.catalog.stage      Idea, Outline, Drafted, Rehearsed, Piloted, Delivered (the courses.stages ladder, in order)
--   courses.catalog.format     Class, Webinar
--   courses.references.ref_type  Microsoft Learn, Calibre, Research, Government of Canada
--   books.triage.decision      classified, failed, skipped, dry_run (the values knowledge-triage.py writes)
--   books.triage.moscow        Must, Should, Could (books have no Won't; failed books keep NULL)
--   research.triage.source_type  image, link, link-note, linkedin, video, web, youtube, other
-- Not converted: books.triage.language and research.triage.language (open ISO codes: a new
-- language would make the triage writers fail).
-- A new value later: alter type ... add value '...';

do $$
declare
  spec text[][] := array[
    ['courses','course_stage',  'Idea|Outline|Drafted|Rehearsed|Piloted|Delivered'],
    ['courses','course_format', 'Class|Webinar'],
    ['courses','ref_type',      'Microsoft Learn|Calibre|Research|Government of Canada'],
    ['books','triage_decision', 'classified|failed|skipped|dry_run'],
    ['books','triage_moscow',   'Must|Should|Could'],
    ['research','source_type',  'image|link|link-note|linkedin|video|web|youtube|other']];
  cols text[][] := array[
    ['courses.catalog','stage','courses.course_stage'], ['courses.catalog','format','courses.course_format'],
    ['courses."references"','ref_type','courses.ref_type'],
    ['books.triage','decision','books.triage_decision'], ['books.triage','moscow','books.triage_moscow'],
    ['research.triage','source_type','research.source_type']];
  i int; labels text;
begin
  for i in 1 .. array_length(spec, 1) loop
    if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                   where n.nspname = spec[i][1] and t.typname = spec[i][2]) then
      select string_agg(quote_literal(l), ',') into labels from unnest(string_to_array(spec[i][3], '|')) l;
      execute format('create type %I.%I as enum (%s)', spec[i][1], spec[i][2], labels);
      execute format('create cast (text as %I.%I) with inout as assignment', spec[i][1], spec[i][2]);
    end if;
  end loop;
  for i in 1 .. array_length(cols, 1) loop
    -- empty strings would not cast: store them as NULL (none exist today; guard anyway)
    execute format('update %s set %I = null where %I = %L', cols[i][1], cols[i][2], cols[i][2], '');
    execute format('alter table %s alter column %I type %s using %I::%s',
                   cols[i][1], cols[i][2], cols[i][3], cols[i][2], cols[i][3]);
  end loop;
end $$;

grant usage on type courses.course_stage, courses.course_format, courses.ref_type to pipeline_agent, nocodb_ro;
grant usage on type books.triage_decision, books.triage_moscow to pipeline_agent, nocodb_ro;
grant usage on type research.source_type to pipeline_agent, nocodb_ro;
