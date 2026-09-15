# AI Coding Agent Playbook: Resilient Home-Lab Compose Stack 🤖

Welcome, AI Agent! This document provides the architectural blueprint, structural patterns, and strict resiliency rules governing this repository. Read this playbook thoroughly before modifying or adding services to maintain our production-grade home-lab environment.

---

## 🏗️ Repository Architecture

This stack is organized as a **highly modular, decentralized multi-container deployment** utilizing the modern Docker Compose `include` directive. Instead of a single monolithic compose file, each service is fully self-contained within its own directory.

```
/home/jond/.docker/
├── docker-compose.yml       # Root orchestrator (includes active services)
├── .env.example             # Global environment variables blueprint
├── .gitignore               # Excludes sensitive data (.env, .env.local, config folders)
│
├── searxng/                 # SearXNG metasearch service module
│   ├── docker-compose.yml   # Multi-container: SearXNG + Valkey
│   ├── settings.yml         # SearXNG configuration (zero hardcoded secrets)
│   └── limiter.toml         # Caching & bot rate-limiter profiles
│
├── jellyfin/                # Jellyfin Media Server module
│   └── docker-compose.yml   # Host-networking + AMD GPU acceleration mounts
│
├── qbittorrent/             # Lightweight Downloader module
│   ├── docker-compose.yml   # High performance IO storage bindings
│   └── config/              # Local runtime configuration files
│
├── changedetection/         # Web Monitoring module (Optional)
│   ├── docker-compose.yml   # Changedetection.io + Browser-Sockpuppet-Chrome
│   └── config/              # Scraped data & configurations
│
└── flaresolverr/            # DDoS Bypass Proxy module (Optional)
    └── docker-compose.yml   # Headless Chromium automation engine
```

The root `/home/jond/.docker/docker-compose.yml` serves as the entry point, selectively importing active service configurations:
```yaml
include:
  # - path: ./changedetection/docker-compose.yml
  # - path: ./flaresolverr/docker-compose.yml
  - path: ./searxng/docker-compose.yml
  - path: ./jellyfin/docker-compose.yml
  - path: ./qbittorrent/docker-compose.yml
```

---

## 🌲 Hierarchical Environment Overrides (Crucial)

To allow host-specific overrides to be kept strictly separate from base configurations, we implement a **4-layered environment file hierarchy**. In each service's compose file, environment variables are evaluated sequentially. *Later files override and supersede earlier ones:*

```yaml
env_file:
  - path: ../.env          # Layer 1: Global default settings (e.g. TZ, PUID, paths)
    required: false
  - path: ../.env.local    # Layer 2: Global machine-specific overrides
    required: false
  - path: .env             # Layer 3: Service-specific default settings
    required: false
  - path: .env.local       # Layer 4: Service-specific machine-specific overrides
    required: false
```

### Rules for Environment Variables:
1. **Zero Hardcoded Secrets**: Secrets (like `SEARXNG_SECRET`) must *never* be hardcoded in compose files or settings YAMLs. Pass them dynamically using environment substitution.
2. **Path Parameterization**: Do not hardcode physical host storage directories (e.g. `/mnt/...`). Define them as parameterized variables in the global `.env` and map them inside compose (e.g., `${DOWNLOADS_DIR}`).
3. **Keep it Git-Safe**: Local files containing real values (`.env`, `.env.local`) are strictly excluded from version control via `.gitignore`. Always document new environment variables in `.env.example`.

---

## 🛡️ Mandatory Resiliency Standards

> **Read [`docs/HARD-WON-GOTCHAS.md`](docs/HARD-WON-GOTCHAS.md) before hardening a new
> service.** Every entry there was found by breaking something in production —
> Postgres schema permissions and volume mount points, the `cap_drop: ALL` privilege-drop
> trap, why generic "Chromium in Docker" advice is usually wrong, and why
> `docker compose ps` without `-a` silently passes a crash-looped stack. Rescued from
> the retired Coolify fleet repo 2026-09-07.

To prevent performance degradation, memory leaks, disk exhaustion, or system lockups, **every single container definition** must adhere to these five standards. If you write a service that does not follow these, your implementation is incomplete.

### 1. Resource Boundaries 📉
Every service must contain memory and CPU boundaries inside its `deploy` block to safeguard the host against memory leaks or background loop bugs:
```yaml
deploy:
  resources:
    limits:
      cpus: '1.0'        # Adjust based on workload (e.g. 0.25 for valkey, 2.0 for chrome)
      memory: 512M       # Capped to prevent runaway memory allocation
```

### 2. Log Rotation Constraints 🪵
To protect the host disk from filling up, all container logs must be throttled with strict limits:
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### 3. Zombie Process Reaping 🧟
Any container running browser instances, headless scraping engines, or NodeJS scripts that spawn subprocesses (e.g., Flaresolverr, Browser-Sockpuppet-Chrome) **must** run with:
```yaml
init: true
```
This registers a lightweight init process (e.g., `tini`) inside the container to correctly reap zombie child processes and prevent host OS PID depletion.

### 4. Rigorous Healthchecks 🩺
Always define a robust healthcheck using standard lightweight commands (`wget`, `curl`, `valkey-cli ping`, etc.). Do not rely on implicit health:
```yaml
healthcheck:
  test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:5000/healthz"]
  interval: 10s
  timeout: 5s
  retries: 3
  start_period: 15s
```

### 5. Loopback Binding 🔒
For all administrative interfaces or web engines that should not be exposed globally by default (e.g., SearXNG, qBittorrent, ChangeDetection, Flaresolverr), bind the exposed host port strictly to `127.0.0.1`:
```yaml
ports:
  - "127.0.0.1:${SEARXNG_PORT:-8888}:${SEARXNG_PORT:-8888}"
```

### 6. Capability Hardening 🔒
Every service **must** drop all Linux capabilities and add back only what its actual
entrypoint needs — never leave a container on the Docker default capability set.
Read the entrypoint (`docker run --rm --entrypoint cat <image> <path-to-entrypoint>`)
before guessing. Two patterns cover almost everything in this repo (see
`docs/HARD-WON-GOTCHAS.md`, "Container capabilities"):
```yaml
# s6-overlay / PUID-PGID images (LinuxServer-style, Postgres) that start as root,
# chown their data, then drop to a service user:
cap_drop: [ALL]
cap_add:  [CHOWN, FOWNER, DAC_OVERRIDE, SETUID, SETGID]
security_opt: [no-new-privileges:true]

# Images that already run as a non-root user (no privilege-drop dance needed):
cap_drop: [ALL]
security_opt: [no-new-privileges:true]
```
For a Chromium-based image, do not assume it needs `SYS_ADMIN` or
`seccomp=unconfined` — test the actual image against a real CDP call first; several
in this repo needed neither.

---

## 🔌 Service Configurations Reference

Use the current configurations as guides for implementing new ones:

*   **SearXNG**: Privacy metasearch engine. Relies on `valkey` (Redis fork, memory capped at `128M`, command structured with `--save 30 1 --loglevel warning` for light filesystem persistence).
*   **qBittorrent**: Capped at `2048M` memory. Binds media & download environment paths.
*   **Jellyfin**: Designed with `network_mode: host` to access local network streams and binds host devices `/dev/dri` and `/dev/kfd` for native AMD hardware-accelerated transcoding.
*   **ChangeDetection**: Paired with `browser-sockpuppet-chrome` (running headless Chromium with `SYS_ADMIN` capability, `init: true`, and capped at `1536M` memory/`2.0` CPU limits).
*   **Kali Desktop**: LinuxServer Selkies-based Kali (`linuxserver/docker-baseimage-selkies`). AMD/Vulkan GPU accel via `/dev/dri` (`DRINODE`/`DRI_NODE`, no CUDA — NVIDIA-only), CPU/llvmpipe fallback documented inline. Bind-mounts the real host `/home/jond`. **Deliberately omits `no-new-privileges:true`** (breaks `sudo`, which Kali's toolkit — nmap, aircrack-ng, apt — depends on) and adds `NET_RAW`/`NET_ADMIN` on top of the standard s6-overlay cap set; see `docs/HARD-WON-GOTCHAS.md`. Loopback-bound ports to offset the reduced hardening. Off by default in the root `include:`.

---

## 🛠️ Step-by-Step playbook for adding a new Service

When the user asks you to integrate a new service into the home-lab stack, follow these steps exactly:

### Step 1: Create a Service Directory
Create a dedicated subdirectory for the service (e.g., `./my-service`).

### Step 2: Write the `docker-compose.yml`
Create `./my-service/docker-compose.yml`. Make sure to:
- Use standard images (prefer verified, official, or reputable publishers like LinuxServer).
- Define ports using loopback `127.0.0.1` and customizable env variables (e.g., `${MY_SERVICE_PORT:-9000}`).
- Set up the **4-layered env_file block** pointing to `../.env`, `../.env.local`, `.env`, and `.env.local`.
- Apply **Resource limits**, **Log rotation**, **Healthchecks**, and **init: true** (if running subprocesses).
- Use local folder mappings for config storage (e.g., `./config:/config`).

### Step 3: Update Environments
- Add the default configuration key value pairs to `/home/jond/.docker/.env.example`.
- If the user has a local `.env`, append the new service variables to it with helpful comments.

### Step 4: Register in Orchestrator
Add the service directory relative path to the root `/home/jond/.docker/docker-compose.yml` under `include:`.

---

## 🚦 Verification Command Playbook

Before marking any task as complete, run these commands to verify syntax, config values, and deployment validity:

```bash
# 1. Verify compose syntax and structural formatting
docker compose config

# 2. Start the services (dry-run/daemon mode)
docker compose up -d

# 3. Check health and lifecycle status
docker compose ps

# 4. View logs of specific containers to ensure error-free startups
docker compose logs -f <service-name>
```

Happy hacking, AI Agent! Keep the stack secure, resilient, and blazing fast. 🚀
