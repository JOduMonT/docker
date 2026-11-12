# Atomic CRM (trial) on the shared local Supabase

[Atomic CRM](https://github.com/marmelab/atomic-crm) (React + Supabase) for Jon's
one-person CRM trial. The container serves only the static app; all data lives
in the existing local Supabase (`Shared\docker\supabase`). No second Supabase
stack. Dev only, never on Dokploy.

- URL: <http://localhost:3010> (bound to 127.0.0.1)
- Upstream: cloned to `src\` (git-ignored), pinned at commit `259c179`
  (2026-11-12). To update: `git -C src pull`, then dry-run the migrations, then rebuild.

## Sign in

Email `CRM_ADMIN_EMAIL` and password `CRM_ADMIN_PASSWORD` from `.env` in this
folder (git-ignored). This first user is the CRM administrator (a `sales` row
with `administrator = true`). Change the password in the app's profile page
after the first sign-in. To check that login and contact create/delete still
work: `python scripts/create_admin.py --check-only`.

## Start / stop

```powershell
cd "C:\Users\Jonathan Dumont\OpenBot\Shared\docker\atomic-crm"
docker compose up -d            # start (Supabase must be running)
docker compose down             # stop (data stays in Supabase)
docker compose up -d --build    # rebuild after changing .env or updating src
```

## Images (Jon's policy: free Docker Hardened Image > Alpine > OSS)

| stage | image | why |
|---|---|---|
| build | `dhi.io/node:24-alpine3.22-dev` | free DHI; the `-dev` variant has npm and a shell for the build |
| runtime | `dhi.io/nginx:1-alpine3.22` | free DHI; runs as non-root uid 65532 on port 8080 |

The runtime container is read-only with `no-new-privileges`, 128 MB, port
`127.0.0.1:3010` only. The bundle holds the Supabase **publishable** key, which
is meant for browsers (row-level security protects the data); no server-side
key is in the image (checked).

## What it added to Supabase

Backup taken first, kept outside OpenBot's shared folders because it holds auth
users, role password hashes and paid reference data:
`C:\Users\Jonathan Dumont\Backups\supabase\pre-atomic-crm-20261112-052845.dump`
(+ `.globals.sql`). Restore = `pg_restore` of that file. Delete it when the trial ends.

Applied with `python scripts/apply_migrations.py` (use `--dry-run` first: every
pending file in one transaction, rolled back). 33 upstream migrations,
recorded in `supabase_migrations.schema_migrations` (the Supabase CLI table).
A pending upstream file that drops or alters an extension, touches
pipeline/content/reference/ops/net/vault, grants to PUBLIC or manages roles is
refused until a person reads it and passes `--allow <file>`.

- Schema `public` (was empty) now belongs to the CRM: tables `companies`,
  `configuration`, `contact_notes`, `contacts`, `deal_notes`, `deals`,
  `favicons_excluded_domains`, `sales`, `tags`, `tasks`, `user_invitations`;
  views `activity_log`, `companies_summary`, `contacts_summary`, `init_state`;
  functions (global search, merge contacts, imports, avatars, SSO helpers).
  Row-level security on every table; signed-out requests see nothing.
- Schema `private` (empty helper schema).
- `auth.users`: triggers `on_auth_user_created` / `on_auth_user_updated`.
  **Every future Supabase Auth user becomes a CRM `sales` row.** Today the CRM
  is the only Supabase Auth user of this stack.
- Storage bucket `attachments` with policies for signed-in users.
- Extensions: `http`, `pgjwt`, `unaccent`, `citext` (in schema `extensions`);
  `pg_net` already existed.

### Changes to upstream for the shared stack

- One upstream statement skipped: `DROP EXTENSION pg_net CASCADE` + recreate
  (it would remove Supabase's webhook functions and reopen pg_net to every
  role, undoing `supabase/migrations/005`). pg_net is already in `extensions`.
- `supabase/migrations/007_atomic_crm_hardening.sql` (run as supabase_admin
  after the CRM migrations): the `http` extension's functions are taken away
  from PUBLIC (only postgres, authenticated, service_role keep them); CRM
  functions lose their PUBLIC grant (the CRM's own revokes, e.g. on
  `get_user_id_by_email`, are re-stated); `pipeline_agent`, `dashboard_ro`
  and `ops_app` get nothing in `public`/`private`. Then 005 is re-applied.

## Before anything beyond localhost (Momus review, 2026-11-12)

- The `attachments` bucket is **public**: anyone who can reach the Supabase API
  (today: local processes only) can read a file by its URL without signing in.
  The app links files with `getPublicUrl`, so making it private needs an app
  change to signed URLs. Uploads are capped at 10 MB (007).
- Every signed-in CRM user can read, edit and delete every CRM record (upstream
  policies `using (true)`). Fine for Jon alone; review before adding a second user.
- 007 pins the attachment-cleanup URL to `host.docker.internal:54321` (upstream
  builds it from the token's issuer).

## Not set up (on purpose, trial scope)

- **Edge functions** (`users`, `update_password`, `merge_contacts`,
  `delete_note_attachments`, `postmark`, `mcp`) are not deployed: inviting
  other users from the app, merging contacts, cleaning up deleted note
  attachments and inbound email do not work. Contacts, companies, deals,
  notes, tasks, tags and search do. Deploying them means adding folders to
  the shared Supabase functions volume (a shared-config change: review first).
- **Email**: none. The admin was created with the email already confirmed;
  the stack has no mail container. "Forgot password" will not send anything.
- **Sign-up**: the shared Supabase has `DISABLE_SIGNUP=false`, but the CRM's
  own trigger refuses any sign-up after the first user unless invited or SSO
  (checked by Momus). `DISABLE_SIGNUP=true` would also close it at the gateway
  (shared config: review first).
- **Outbound lookups**: when a contact or company is saved, the CRM may call
  gravatar.com (with a hash of the email) and favicon.show (with the domain)
  from inside Postgres.
