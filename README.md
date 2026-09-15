# Resilient Home-Lab Docker Compose Stack 🚀

This repository contains a highly optimized, production-grade, and resilient multi-container Docker Compose layout designed for home-lab services. It includes search, media streaming, downloads, change detection, and headless browsing engines bound together by a robust, secure environment overriding system.

---

## 🏗️ Services Overview

1.  **[SearXNG](https://docs.searxng.org/)**: A privacy-respecting, self-hosted metasearch engine.
2.  **[Valkey](https://valkey.io/)**: A high-performance, open-source key-value database (fully API-compatible Redis fork) acting as SearXNG's caching and rate-limiting (bot-protection) backend.
3.  **[qBittorrent](https://www.qbittorrent.org/)**: A lightweight, secure torrent downloader (includes automated, custom Python search engine setups).
4.  **[Jellyfin](https://jellyfin.org/)**: The ultimate voluntary media system for organizing and streaming your private libraries (configured with host-networking and AMD hardware acceleration).
5.  **[ChangeDetection.io](https://changedetection.io/)**: (Optional) Powerful self-hosted website change monitoring engine.
6.  **[Flaresolverr](https://github.com/FlareSolverr/FlareSolverr)**: (Optional) Proxy server to bypass DDoS protection mechanisms for scraping and indices.
7.  **[Browser](https://github.com/coollabsio/openclaw)**: (Optional) Shared Chrome/CDP sidecar — a real browser on tap for scraping and automation, with a web desktop UI. Migrated here 2026-09-07 from its own repo.
8.  **[MetaMCP](https://github.com/metatool-ai/metamcp)**: (Optional) MCP gateway with a bundled hardened Postgres 18. Migrated here 2026-09-07 from its own repo.
9.  **[Kali Desktop](https://docs.linuxserver.io/images/docker-kali-linux/)**: (Optional) Full Kali Linux desktop streamed to the browser via Selkies, with AMD/Vulkan GPU acceleration for a Radeon 780M iGPU and the host's `/home/jond` mounted in.

> **Production note:** production self-hosting runs on [Cloudron](https://cloudron.io) (automatic maintenance, updates and backups). This repo is the **local Docker + Docker Compose** side. The former Coolify fleet is retired; the hard-won operational lessons from it are preserved in [`docs/HARD-WON-GOTCHAS.md`](docs/HARD-WON-GOTCHAS.md).

---

## 💪 Core Architecture & Resiliency Upgrades

This compose stack is built with the highest standards of production container orchestration:

### 1. 📌 Pinned Image Versions
Every image is pinned to a specific version tag (never `:latest`), so upgrades are
explicit and reviewable rather than silent. [Renovate](https://docs.renovatebot.com/)
runs weekly (`.github/workflows/check-upstream-release.yml`) to open version-bump PRs
as upstream releases land.

### 2. 🔒 Container Hardening
Every container drops all Linux capabilities by default (`cap_drop: [ALL]`) and adds
back only what its entrypoint actually needs — the s6-overlay/PUID-PGID root→user
privilege-drop set for LinuxServer-style images, or nothing at all for images that
already run as non-root. `security_opt: [no-new-privileges:true]` is set throughout.
See [`docs/HARD-WON-GOTCHAS.md`](docs/HARD-WON-GOTCHAS.md) for the reasoning and the
traps this avoids (a bare `cap_drop: ALL` breaks the root→user drop dance).

### 3. 🌲 Hierarchical Environment Overrides
All service definitions support a modern, 4-layered environment file hierarchy. Variables are evaluated sequentially (later files override/supersede earlier ones), allowing host-specific overrides to be kept strictly separate from the base configurations:
```yaml
    env_file:
      - path: ../.env          # Global default settings
        required: false
      - path: ../.env.local    # Global machine-specific overrides
        required: false
      - path: .env             # Service-specific default settings
        required: false
      - path: .env.local       # Service-specific machine-specific overrides
        required: false
```

### 4. 🛡️ 100% Secure & Public Ready
*   **Zero Hardcoded Secrets**: Cryptographic keys like `SEARXNG_SECRET` are passed dynamically from `.env` using environment variables. No secrets are stored in `settings.yml`.
*   **Privacy-Friendly Directory Mounts**: Your physical host storage directories (e.g. `/mnt/...`) are kept in your local `.env` and are strictly excluded from version control via `.gitignore`.
*   **Clean `.env.example`**: A fully commented template is provided for a seamless open-source setup experience.

### 5. 📉 Resource Boundaries
Every container is capped with memory and CPU boundaries using Docker's `deploy.resources.limits` configuration to prevent memory leaks or background loop bugs from freezing your host system.

### 6. 🪵 Log Rotations
To protect your host disk from filling up, all containers are constrained to standard JSON file logging rotations (`max-size: "10m"`, `max-file: "3"`).

### 7. 🧟 Zombie Process Reaping
Containers running headless Chromium instances (`browser-sockpuppet-chrome` and `flaresolverr`) are configured with `init: true`. This invokes the lightweight Docker init-system to automatically reap zombie child processes.

---

## ⚡ Quick-Start & Deployment

### Prerequisite: Set Up Environment Files
1.  Clone this repository to your host machine.
2.  Copy the template file to `.env`:
    ```bash
    cp .env.example .env
    ```
3.  Open the newly created `.env` file and customize the volume paths (`MEDIA_BOOKS`, `DOWNLOADS_DIR`, etc.) to point to your storage directories.
4.  Generate a unique, cryptographically secure key for SearxNG and add it to your `.env` under `SEARXNG_SECRET`:
    ```bash
    openssl rand -hex 32
    ```
5.  If you're enabling the optional MetaMCP service, generate its two required secrets the same way and set them under `BETTER_AUTH_SECRET` and `METAMCP_POSTGRES_PASSWORD` — both fail the container on startup if left as the placeholder.

### Running the Services
Bring up the entire stack in the background:
```bash
docker compose up -d
```

Check the health status of all running containers:
```bash
docker compose ps
```

---

## 📋 Default Port Configurations

| Service | Host Port | Internal Port | Environment Override Key |
| :--- | :--- | :--- | :--- |
| **SearXNG** | `8888` | `8888` | `SEARXNG_PORT` |
| **qBittorrent** | `8080` | `8080` | `QBITTORRENT_PORT` |
| **ChangeDetection** | `5000` | `5000` | `CHANGEDETECTION_PORT` |
| **Flaresolverr** | `8191` | `8191` | `FLARESOLVERR_PORT` |
| **Jellyfin** | *Host Network* | `8096` | *Managed via Host Net* |
| **Browser** (web UI) | `3000` | `3000` | `BROWSER_UI_PORT` |
| **Browser** (CDP) | `9223` | `9223` | `BROWSER_CDP_PORT` |
| **MetaMCP** | `12008` | `12008` | `METAMCP_PORT` |
| **Daily Stars Explorer** | `8080` | `8080` | `DAILY_STARS_PORT` |
| **Kali Desktop** (HTTP) | `3010` | `3000` | `KALI_DESKTOP_HTTP_PORT` |
| **Kali Desktop** (HTTPS) | `3011` | `3001` | `KALI_DESKTOP_HTTPS_PORT` |

---

## 🖥️ Kali Desktop: GPU, persistence, and installing apps

Optional service, off by default. Uncomment `./kali-desktop/docker-compose.yml`
in the root `include:` block to enable it.

**Start it:**
```bash
docker compose up -d kali-desktop
```

**Access it:** open `https://localhost:3011` (accept the self-signed cert —
HTTPS is required for clipboard/audio/file transfer). The plain HTTP port
(`3010`) also works for a quick check but skips those features. Both are
loopback-bound by default; widen only behind a VPN or reverse proxy, since
this container has `sudo` and full access to Kali's toolkit.

**GPU (AMD Radeon 780M):** accelerated by default via `/dev/dri` + Mesa/Vulkan
(no CUDA — that's NVIDIA-only). If `KALI_GPU_RENDER_GID`/`KALI_GPU_VIDEO_GID`
in `.env` don't match your host, check with `getent group render video`. To
fall back to CPU/software rendering (Mesa llvmpipe), comment out the
`devices:`, `group_add:`, and `DRINODE`/`DRI_NODE`/`PIXELFLUX_WAYLAND` lines in
`kali-desktop/docker-compose.yml` — no other changes needed.

**What persists across `docker compose up -d --force-recreate`:**
- `kali-desktop/config/` → the desktop user's home (`/config`): dotfiles,
  `~/.config`, `~/.local`, Desktop, Downloads.
- `kali-desktop/opt/` → `/opt`, where many `.deb` packages (including
  Obsidian) install their payload.
- Your real `/home/jond`, bind-mounted read-write at the same path.

**Installing a manual `.deb` app (e.g. Obsidian) so it survives a recreate:**

Method A — no root, guaranteed to persist (recommended):
```bash
mkdir -p ~/Applications && cd ~/Applications
wget https://github.com/obsidianmd/obsidian-releases/releases/download/v1.13.7/obsidian_1.13.7_amd64.deb
dpkg-deb -x obsidian_1.13.7_amd64.deb obsidian
mkdir -p ~/.local/bin ~/.local/share/applications
ln -sf ~/Applications/obsidian/opt/Obsidian/obsidian ~/.local/bin/obsidian
# copy the app's .desktop file and fix its Exec= line to the symlink above
cp ~/Applications/obsidian/usr/share/applications/*.desktop ~/.local/share/applications/
```
Everything here lives under `/config`, which is already persisted.

Method B — real `apt`/`dpkg` install (integrates with the package manager, but
needs a re-run after recreate):
```bash
sudo dpkg -i obsidian_1.13.7_amd64.deb
```
The payload lands in `/opt` (persisted), but the `dpkg` database entry and the
`/usr/bin` symlink/desktop entry are not (only `/config` and `/opt` are
volumed). After a container recreate, keep the `.deb` under `~/Downloads`
(persisted) and re-run `sudo dpkg -i` — it's fast since the `/opt` payload is
already there, it just relinks.

---

## 📜 License

MIT — see [`LICENSE`](LICENSE).
