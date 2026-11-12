# NocoDB, official image (Alpine-based; no Docker Hardened Image exists for NocoDB),
# pinned, re-based only to run as the unprivileged `node` user instead of root.
FROM nocodb/nocodb:2026.10.1
RUN mkdir -p /usr/app/data && chown node:node /usr/app/data
USER node
