# Security Policy

A home-lab Docker Compose stack for self-hosted services: SearXNG with Valkey, Jellyfin, qBittorrent, changedetection, a browser sidecar, MetaMCP, FlareSolverr, Hindsight and a Kali desktop.

## Supported versions

Only the current `main` branch is supported.
Fixes land on `main`; there are no release branches.

## Reporting a vulnerability

Please report privately.
Do not open a public issue or pull request.

- **Preferred:** [report a vulnerability](https://github.com/JOduMonT/docker/security/advisories/new) through GitHub private vulnerability reporting.
- **Email:** jodumont+security@gmail.com
- Include what you found, the affected file or service, steps to reproduce and the impact you see.
- Do not access, change or delete data that is not yours, and do not run denial-of-service or automated scanning against live systems.

You can expect an acknowledgement within 3 business days and a status update within 10.
Confirmed issues are fixed as quickly as severity allows, and you are credited in the fix unless you prefer not to be.

## Scope

In scope:

- Compose files: published ports, `privileged` or host-network settings, volume mounts that expose the host, services reachable without authentication.
- `.env.example` defaults and CI workflows.
- A real secret ending up in the repository.

Out of scope:

- Vulnerabilities inside the upstream images (SearXNG, Jellyfin, qBittorrent, Kali and the rest): report them to the upstream project.
- Social engineering and physical attacks.

## How this repository is kept safe

- Dependabot alerts and security updates are on; a vulnerable dependency gets an automatic pull request.
  Routine version bumps are opened by Renovate, and `.github/dependabot.yml` keeps Dependabot's own version updates off to avoid duplicate pull requests.
- Dependabot pull requests are merged automatically by `.github/workflows/dependabot-auto-merge.yml` once every other check passes.
  Major version bumps are left open for review.
- GitHub secret scanning with push protection and CodeQL code scanning are enabled.
- `.env.example` carries placeholders only; the real `.env` is never committed.
- Image bumps arrive through Renovate and are validated by the CI compose check and smoke test before merge.
