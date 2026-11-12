-- 009_data_store_debt.sql
-- Inventory of file-based data stores ("migration debt") that the
-- "Data lives in Supabase" doctrine (wiki team-doctrine.md, 2026-11-12)
-- says to move into Supabase, keep as documented exceptions, or delete.
-- Schema + seed + the one explicit grant nocodb_ro needs to see it in NocoDB.
-- Idempotent: re-running upserts the same rows. Apply as postgres.

create table if not exists ops.data_store_debt (
  id          bigint generated always as identity primary key,
  path        text not null unique,               -- path relative to OpenBot root
  file_type   text not null,                      -- csv | tsv | jsonl | json | sqlite | db | xlsx
  owner_agent text,                               -- agent that owns/uses the store
  purpose     text,
  row_count   bigint,                             -- data rows (NULL for object stores / databases)
  decision    text not null check (decision in ('migrate','keep','delete')),
  status      text not null default 'pending' check (status in ('pending','reviewing','migrating','migrated','kept','delete-approved')),
  notes       text,
  detected_at timestamptz not null default now()
);

-- nocodb_ro: explicit per-table grant (no default privileges), so Jon sees this in NocoDB.
grant select on ops.data_store_debt to nocodb_ro;

insert into ops.data_store_debt (path, file_type, owner_agent, purpose, row_count, decision, status, notes) values
  -- ai-training-courses (Chiron): the known example of migration debt
  ('Shared/ai-training-courses/data/courses.csv',      'csv',  'Chiron', 'course catalog', 16,    'migrate', 'pending', null),
  ('Shared/ai-training-courses/data/notes.csv',        'csv',  'Chiron', 'course notes',   5,     'migrate', 'pending', null),
  ('Shared/ai-training-courses/data/references.csv',   'csv',  'Chiron', 'course references', 101, 'migrate', 'pending', null),
  ('Shared/ai-training-courses/data/stages.csv',       'csv',  'Chiron', 'course stages',  6,     'migrate', 'pending', null),

  -- books-triage-pipeline
  ('Shared/books-triage-pipeline/reports/changes.csv',      'csv',   'booklet-slicer', 'book change log',      13130, 'migrate', 'pending', null),
  ('Shared/books-triage-pipeline/reports/changes.jsonl',    'jsonl', 'booklet-slicer', 'book change log',      0,     'migrate', 'pending', 'empty log'),
  ('Shared/books-triage-pipeline/reports/research-log.jsonl','jsonl', 'booklet-slicer', 'research log',         764,   'migrate', 'pending', null),
  ('Shared/books-triage-pipeline/reports/triage.jsonl',     'jsonl', 'booklet-slicer', 'triage decisions',     705,   'migrate', 'pending', null),
  ('Shared/books-triage-pipeline/reports/triage.csv',       'csv',   'booklet-slicer', 'triage decisions',     3077,  'migrate', 'pending', null),
  ('Shared/books-triage-pipeline/reports/taxonomy.json',    'json',  'booklet-slicer', 'book taxonomy',        845,   'migrate', 'pending', null),

  -- career-ops (Athena)
  ('Shared/career-ops/data/Connections.csv',         'csv',  'Athena', 'LinkedIn connections',      635,  'migrate', 'pending', null),
  ('Shared/career-ops/data/contacts.tsv',            'tsv',  'Athena', 'contacts',                 11,   'migrate', 'pending', null),
  ('Shared/career-ops/data/portal-health.tsv',       'tsv',  'Athena', 'job portal health checks', 2250, 'migrate', 'pending', null),
  ('Shared/career-ops/data/scan-history.tsv',        'tsv',  'Athena', 'scan history',             908,  'migrate', 'pending', null),
  ('Shared/career-ops/data/scan-runs.tsv',           'tsv',  'Athena', 'scan runs',                34,   'migrate', 'pending', null),
  ('Shared/career-ops/data/status-log.tsv',          'tsv',  'Athena', 'status log',               31,   'migrate', 'pending', null),
  ('Shared/career-ops/data/salary-observations.tsv', 'tsv',  'Athena', 'salary observations',      3,    'migrate', 'pending', null),
  ('Shared/career-ops/data/pdf-index.tsv',           'tsv',  'Athena', 'PDF index',                10,   'migrate', 'pending', null),
  ('Shared/career-ops/data/intake-state.json',       'json', 'Athena', 'intake state',             null, 'migrate', 'pending', 'one JSON object'),

  -- kobo-panel
  ('Shared/kobo-panel/data/brief.json', 'json', 'kobo-panel', 'panel brief', null, 'migrate', 'pending', 'one JSON object'),

  -- OpenBot platform's own shared-table store (not an agent-created ad-hoc file)
  ('Shared/Data/agent-data.db', 'sqlite', 'OpenBot platform', 'built-in shared tables (frontdesk, marketplace_scan, prospect_*, promptlib stats)', null, 'keep', 'kept', 'platform store used by openbot.query_data/execute_data; business rows are candidates to move to Supabase later'),

  -- prompt library (Jon''s existing system, embeddings included)
  ('Shared/openbot-promptlib/data/promptlib.sqlite', 'sqlite', 'prompt library', 'items, ratings, usage + sqlite-vec embeddings', null, 'keep', 'kept', 'existing system; migration is its own project'),

  -- yes-decks: raw source already mirrored to reference.yes_cards
  ('Shared/Data/yes-decks/cards.A.json', 'json', 'yes-decks', 'paid YES cards source', null, 'keep', 'kept', 'raw source; licensed material'),
  ('Shared/Data/yes-decks/cards.B.json', 'json', 'yes-decks', 'paid YES cards source', null, 'keep', 'kept', 'raw source; licensed material'),
  ('Shared/Data/yes-decks/cards.C.json', 'json', 'yes-decks', 'paid YES cards source', null, 'keep', 'kept', 'raw source; licensed material'),
  ('Shared/Data/yes-decks/merged.json', 'json', 'yes-decks', 'paid YES cards source (merged)', null, 'keep', 'kept', 'loaded into reference.yes_cards'),

  -- copilot-practice-lab: sample/seed data for a course lab (course content)
  ('Shared/copilot-practice-lab/data/documents.json',  'json', 'practice lab', 'sample documents',   null, 'keep', 'kept', 'lab sample data'),
  ('Shared/copilot-practice-lab/data/permissions.json','json', 'practice lab', 'sample permissions', null, 'keep', 'kept', 'lab sample data'),
  ('Shared/copilot-practice-lab/data/teams.json',      'json', 'practice lab', 'sample teams',       null, 'keep', 'kept', 'lab sample data'),
  ('Shared/copilot-practice-lab/data/users.csv',       'csv',  'practice lab', 'sample users',       19,   'keep', 'kept', 'lab sample data'),
  ('Shared/copilot-practice-lab/content/programs-program-data-2025.csv',      'csv', 'practice lab', 'course content dataset', 5,  'keep', 'kept', 'course content'),
  ('Shared/copilot-practice-lab/content/programs-prompt-library.csv',         'csv', 'practice lab', 'course content dataset', 0,  'keep', 'kept', 'course content'),
  ('Shared/copilot-practice-lab/content/sharedold-salary-bands-draft.csv',    'csv', 'practice lab', 'course content dataset', 3,  'keep', 'kept', 'course content'),
  ('Shared/copilot-practice-lab/content/sharedold-volunteer-list-2023.csv',   'csv', 'practice lab', 'course content dataset', 6,  'keep', 'kept', 'course content; contains phone numbers'),

  -- wiki research snapshot
  ('Shared/wiki/research/triage/triage.csv', 'csv', 'wiki', 'research triage snapshot', 67, 'keep', 'kept', 'research artifact'),

  -- career-ops batch additions (raw source inputs, already merged into tracker)
  ('Shared/career-ops/batch/tracker-additions/merged/', 'tsv', 'Athena', 'raw batch additions to tracker (30 TSV)', null, 'keep', 'kept', 'source inputs'),

  -- product-pipeline: pre-Supabase stores, archived (delete pending Jon approval)
  ('Shared/product-pipeline/_archive/2026-11-11-pre-supabase/pipeline.db',                     'sqlite', 'product pipeline', 'pre-Supabase pipeline DB',       null, 'delete', 'pending', 'archived; superseded by Supabase'),
  ('Shared/product-pipeline/_archive/2026-11-11-pre-supabase/raw-volume/pipeline.db',          'sqlite', 'product pipeline', 'pre-Supabase raw-volume DB',     null, 'delete', 'pending', 'archived; superseded by Supabase'),
  ('Shared/product-pipeline/_archive/2026-11-11-pre-supabase/api/data_test/test.db',           'sqlite', 'product pipeline', 'test DB',                          null, 'delete', 'pending', 'archived'),
  ('Shared/product-pipeline/_archive/2026-11-11-pre-supabase/api/excel/pipeline-dashboard-new.xlsx', 'xlsx', 'product pipeline', 'dashboard export', null, 'delete', 'pending', 'archived; superseded'),
  ('Shared/product-pipeline/_archive/2026-11-11-pre-supabase/api/excel/pipeline-dashboard.xlsx',     'xlsx', 'product pipeline', 'dashboard export', null, 'delete', 'pending', 'archived; superseded'),
  ('Shared/product-pipeline/_archive/2026-11-11-pre-supabase/engagement/linkedin-comments.jsonl',    'jsonl', 'Calliope', 'old engagement log (comments)', null, 'delete', 'pending', 'the known Calliope conversation JSONL debt'),
  ('Shared/product-pipeline/_archive/2026-11-11-pre-supabase/engagement/posts.jsonl',                'jsonl', 'Calliope', 'old engagement log (posts)',    null, 'delete', 'pending', 'archived; superseded by Supabase')
on conflict (path) do update set
  file_type   = excluded.file_type,
  owner_agent = excluded.owner_agent,
  purpose     = excluded.purpose,
  row_count   = excluded.row_count,
  decision    = excluded.decision,
  status      = excluded.status,
  notes       = excluded.notes;
