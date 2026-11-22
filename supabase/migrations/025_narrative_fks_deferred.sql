-- 025_narrative_fks_deferred.sql  (apply as postgres, the apply.py default)
-- Fix for 021: pipeline_db sync replaces content.narratives wholesale (delete all, re-insert, one
-- transaction). The new posts.narrative_id and campaigns.narrative_id FKs made the delete fail at once,
-- breaking the sync writer. Checking them at commit lets the same narratives come back; a narrative that a
-- post or campaign still points to cannot be dropped for good (sync then fails at commit, by design).
alter table content.posts     alter constraint posts_narrative_id_fkey     deferrable initially deferred;
alter table content.campaigns alter constraint campaigns_narrative_id_fkey deferrable initially deferred;
