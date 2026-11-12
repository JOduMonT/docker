# NocoDB (local, dev only)

[NocoDB](https://github.com/nocodb/nocodb): an Airtable-style spreadsheet view over
our local Supabase data. Runs on k12 only, never on Dokploy.

- URL: <http://localhost:8091> (bound to 127.0.0.1)
- Sign in: `NC_ADMIN_EMAIL` / `NC_ADMIN_PASSWORD` from `.env` in this folder
  (git-ignored). Change the password at first sign-in (account menu).
- Base **Supabase (read-only)**: sources `pipeline`, `content`, `ops`.

## Start / stop

```powershell
cd "C:\Users\Jonathan Dumont\OpenBot\Shared\docker\nocodb"
docker compose up -d            # start (takes ~1 min to become healthy)
docker compose down             # stop; NocoDB's own data stays in volume nocodb_nocodb-data
docker compose up -d --build    # after changing the version in Dockerfile
python scripts/connect_supabase.py --check-only   # tables visible, a write is refused
```

## Image (Jon's policy: free Docker Hardened Image > Alpine > official)

No Docker Hardened Image exists for NocoDB. The official image
`nocodb/nocodb:2026.10.1` is Alpine-based, so it is used, pinned, and rebuilt
only to run as the unprivileged `node` user instead of root. The container
drops all capabilities, has `no-new-privileges`, 1.5 GB memory, and listens
on `127.0.0.1:8091` only.

## Licence

Since 2026-01-08 NocoDB is under the **Sustainable Use License** (fair-code,
not OSI open source): use and modify for your own internal business,
non-commercial or personal use; do not sell it or offer it to others as a
service. Jon's internal use fits; hosting it for clients would not.

## Data

- NocoDB's own metadata (users, views, source settings) is SQLite in the
  Docker volume `nocodb_nocodb-data`, not in Supabase.
- Data-source credentials in it are encrypted with `NC_CONNECTION_ENCRYPT_KEY`
  (`.env`). Back up `.env` with the volume: without that key the sources
  cannot be opened.
- Telemetry and error reports are off (`NC_DISABLE_TELE`,
  `NC_DISABLE_ERR_REPORTS`); sign-up is invite-only.
- `NC_ALLOW_LOCAL_EXTERNAL_DBS=true` lets NocoDB reach the local Supabase;
  webhooks and other outbound calls keep NocoDB's SSRF protection.

## Supabase access (role `nocodb_ro`, migration `supabase/migrations/008_nocodb_ro.sql`)

Connects through the **session** pooler `host.docker.internal:54322` as
`nocodb_ro.openbot` (never the transaction pooler, never postgres or
service_role). Password: `NOCODB_RO_PASSWORD` in this `.env` only; `apply.py`
reads it from here.

- Reads every table and view that existed in `pipeline`, `content`, `ops`
  when 008 ran. Nothing in `reference` (the paid YES Decks cards), `auth`,
  `storage`, `vault`, `private`, `net` or `extensions`; no functions.
- Read-only three ways: SELECT-only grants and RLS policies, the role's
  `default_transaction_read_only`, and NocoDB's own read-only source flags.
- New tables are **not** exposed automatically: a migration that adds one
  NocoDB should show grants SELECT and adds the `nocodb_ro_read` policy.
- To let Jon edit later: grant INSERT/UPDATE on chosen tables plus matching
  policies in a new migration, drop the read-only setting, and untick
  "read-only" on the source in NocoDB. Review first (shared Supabase).
- The role allows 5 connections; each NocoDB source uses a pool of 1.
