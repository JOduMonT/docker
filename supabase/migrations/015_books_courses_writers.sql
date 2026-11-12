-- 015_books_courses_writers.sql
-- Write path for the agents that used to write the migrated files (Jon: "repoint, then delete").
--   books.*   <- books-triage-pipeline scripts (knowledge-triage.py, apply_triage_batch.py)
--   courses.* <- Chiron (catalog, notes, references, stages)
--   (kobo.briefs: no writer. Jon kept brief.json as a file; the table is a frozen 2026-11-10 snapshot.)
-- Role: the existing agent write role pipeline_agent (same as 010), so no new secret.
-- Logs are append-only (no UPDATE/DELETE); edited reference tables get UPDATE; no DELETE anywhere.
-- RLS on every table, same pattern as 010: one policy for the writer, one read policy for nocodb_ro.

-- Natural keys the writers upsert on (verified unique: 845/845 slugs, 16/16 course ids).
create unique index if not exists taxonomy_slug_uniq on books.taxonomy (slug);
create unique index if not exists catalog_legacy_id_uniq on courses.catalog (legacy_id);
-- "Is this book already triaged?" lookups.
create index if not exists triage_source_hash_idx on books.triage (source_hash);

grant usage on schema books to pipeline_agent;      -- courses: already granted in 010

-- books: three logs are append-only; taxonomy is updated (seen_count, last_seen).
grant select, insert on books.changes, books.research_log, books.triage to pipeline_agent;
grant select, insert, update on books.taxonomy to pipeline_agent;

-- courses: Chiron edits the catalog and its notes/references; stages is a lookup.
grant select, insert, update on courses.catalog, courses.notes, courses.references, courses.stages to pipeline_agent;

do $$
declare t text;
begin
  foreach t in array array['books.changes','books.research_log','books.triage','books.taxonomy',
                           'courses.catalog','courses.notes','courses.references','courses.stages'] loop
    execute format('alter table %s enable row level security', t);
    execute format('drop policy if exists pipeline_agent_write on %s', t);
    execute format('create policy pipeline_agent_write on %s for all to pipeline_agent using (true) with check (true)', t);
    execute format('drop policy if exists nocodb_ro_read on %s', t);
    execute format('create policy nocodb_ro_read on %s for select to nocodb_ro using (true)', t);
  end loop;
end $$;
