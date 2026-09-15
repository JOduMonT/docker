# Hard-won gotchas

Rescued 2026-09-07 from `coolify-apps/CLAUDE.md` before that repo was archived.

Every entry below was **found by breaking something in production**, not read in a
changelog. They are kept because they are about **Docker, Postgres and GitHub
Actions** — not about Coolify, which this setup no longer uses. The
Coolify-specific half of the original document (its API quirks, `ports_exposes`
defaults, `fqdn`/`custom_labels` staleness, root-vs-non-root SSH to the Coolify
host) was deliberately left behind.

---

## Postgres

**Postgres 15+ revokes `CREATE` on the `public` schema from `PUBLIC`.**
`CREATE DATABASE` + `CREATE USER` + `GRANT ALL PRIVILEGES ON DATABASE` is *not*
enough. The app connects fine and then dies on its first migration with
`permission denied for schema public`, which surfaces as a crash-looping
container rather than an obvious permission error. Also run, inside the new
database:

```sql
GRANT ALL ON SCHEMA public TO <user>;
```

**Postgres 18+ changed the expected volume mount point.** Older images expect
`/var/lib/postgresql/data`; 18+ wants a single mount at `/var/lib/postgresql` and
manages the version-specific subdirectory itself (to support `pg_upgrade --link`).
Mounting the old path crash-loops the container on start — **even against a
completely empty volume**. The log explains it if you read it. Found by deploying,
not from release notes. See `metamcp/docker-compose.yml` for the correct form.

**Postgres major versions are not in-place upgradeable by swapping the image
tag.** The migration path is: `pg_dumpall` from the old instance → verify it
restores cleanly into a *throwaway* container of the target version **first** →
point the compose file at a **new, differently-named volume** (keeping the old one
as an automatic rollback point) → redeploy → restore into the fresh instance.

## Container capabilities

**`cap_drop: ALL` breaks any image whose entrypoint drops privileges from root.**
The s6-overlay / PUID-PGID pattern (LinuxServer-style images, the Postgres
official image, and others) starts as root, `chown`s its data, then drops to the
service user. Bare `cap_drop: ALL` breaks that dance and the container
crash-loops. The working set is:

```yaml
cap_drop: [ALL]
cap_add:  [CHOWN, FOWNER, DAC_OVERRIDE, SETUID, SETGID]
```

**Generic "run Chromium in Docker" advice is frequently wrong for the specific
image you are using.** The usual `cap_add: SYS_ADMIN` / `seccomp=unconfined`
recipe assumes Chrome's own sandbox is the problem. For `coollabsio/openclaw-browser`
it is not: live-tested with **zero** extra capabilities — including a real CDP
`Page.navigate` to a real URL — it worked cleanly, no sandbox errors. What it
actually needed was the same privilege-drop set as Postgres above, for the same
underlying reason. **Test the actual image before importing advice about its
class.**

**`security_opt: [no-new-privileges:true]` silently breaks `sudo` (and any
other setuid binary).** It stops the kernel from honoring the setuid bit on
`execve`, which is how `sudo` gains root in the first place — the binary still
runs, it just never elevates, so the failure mode is "command ran, did
nothing privileged" rather than an obvious permission error. Fine for images
that never need setuid escalation (the vast majority in this repo). Wrong for
`kali-desktop`, whose entire toolkit (`nmap` raw/SYN scans, `aircrack-ng`,
wireless tooling, `apt` itself) is built around `sudo`. That service
intentionally omits the flag and relies on loopback-only port binding instead
— see `kali-desktop/docker-compose.yml`.

**Passing local tests do not guarantee the config survives a real first boot.** A
second image in the same deployment passed local testing under `cap_drop: ALL`
and then crash-looped in production, because the local runs never combined the
full hardening block with a genuinely fresh container (no persisted `/data`), and
its entrypoint does one-time `chown -R` / `rm -rf` setup as root on first boot.
**Reproduce the exact hardening block against a genuinely empty volume** before
trusting it.

## Docker operations

**`docker compose ps` without `-a` only lists *running* containers.** A
crash-loop check built on plain `ps` cannot see anything that already died — it
reports success even when every container in the stack has exited. Always use
`ps -a`. This bug shipped live in the smoke-test workflow for a while; the fixed
version is in `.github/workflows/smoke-test.yml`.

**A single-sample health check false-positives on a crash-looping container.** A
container that is actively restarting can be sampled mid-cycle and read as
`running` for exactly one poll. Require several *consecutive* successful reads
(3, ~30s) before declaring success, resetting the streak on any non-running read.
Reproduced live: 14 consecutive `exited:unhealthy` reads, then one lucky
`running:healthy` sample that an unfixed check would have accepted.

**Imperative container configuration does not survive a recreate.** `exec`-ing
into a running container to change state — an `ACL SETUSER` grant, a hand-created
Postgres role, a vector collection created by a one-off API call — only changes
the running process's in-memory state. Unless it is also written somewhere the
next container recreation reads from (a mounted config file, an aclfile, a
migration that runs on start), it is gone on the next `up`.

**An image's entrypoint can gate startup on a fixed list of recognised env vars,
even when a real working config was supplied through a more general mechanism.**
Seen live: an image supported a generic `*_CONFIG_JSON` deep-merge var, but its
entrypoint's "is anything configured?" check only knew a fixed list of named vars
and refused to start (`exit 1`) despite a perfectly valid JSON-defined config. Fix
was an inert placeholder purely to satisfy the gate. **Read the actual entrypoint**
(`docker run --rm --entrypoint cat <image> <path>`) rather than assuming the
documented generic mechanism is sufficient to boot.

**A reverse proxy may not route a container until it reports `healthy`.** Traefik
does not route containers that declare a healthcheck while they sit in `starting`
— requests 503 with `no available server` (which means "no router matched", so
look at routing, not the app) even though the container is `running` and its app
answers on its port. Keep healthcheck intervals and `start_period` short, or the
service is invisible for that whole window. Generic to healthcheck-aware proxies,
not specific to any one platform.

## GitHub Actions

**A reusable workflow's `permissions:` block can only *narrow* the caller's
token, never widen it.** A reusable workflow declaring `contents: write,
pull-requests: write` has no effect if the calling repo's own workflow — or the
repo's default — already restricts it. Repos default to read-only Actions tokens,
which makes an upstream-release or Renovate job silently do nothing: exit 0, zero
changes, no error. Set the permission in the **calling** workflow.

**Moving a published git tag** (e.g. a floating `@v1`) is flagged by branch/tag
protection and by consumers pinning to it. Prefer immutable tags for anything
another repo depends on.
