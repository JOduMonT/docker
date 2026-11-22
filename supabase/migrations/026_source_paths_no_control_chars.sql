-- 026_source_paths_no_control_chars.sql  (apply as postgres, the apply.py default)
-- Same guard as 024 for the other path columns: content.narratives.source_path and
-- content.stories.source_path refuse C0/C1 control characters (a backslash path written in a
-- non-raw Python string). Live rows: 0 offenders (checked 2026-11-12).
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'narratives_source_path_no_control_chars') then
    alter table content.narratives add constraint narratives_source_path_no_control_chars
      check (coalesce(source_path, '') !~ '[\x01-\x1f\x7f-\x9f]');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'stories_source_path_no_control_chars') then
    alter table content.stories add constraint stories_source_path_no_control_chars
      check (coalesce(source_path, '') !~ '[\x01-\x1f\x7f-\x9f]');
  end if;
end $$;