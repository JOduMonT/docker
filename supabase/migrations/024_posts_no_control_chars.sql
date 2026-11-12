-- 024_posts_no_control_chars.sql  (apply as postgres, the apply.py default)
-- 2026-11-12: four content.posts.asset values held U+0082 where "\2026" had been written in a
-- non-raw Python string ("\202" octal escape). Paths with a control character are always a bug,
-- so the database refuses them for every writer (pipeline_db's sql command also checks params).
-- All live rows pass (checked before apply: 0 rows with C0/C1 controls in any text column).
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'posts_paths_no_control_chars') then
    alter table content.posts add constraint posts_paths_no_control_chars check (
      coalesce(asset, '') !~ '[\x01-\x1f\x7f-\x9f]'
      and coalesce(narrative, '') !~ '[\x01-\x1f\x7f-\x9f]'
      and coalesce(link, '') !~ '[\x01-\x1f\x7f-\x9f]');
  end if;
end $$;
