# Atomic CRM (marmelab/atomic-crm) frontend: static React build served by nginx.
# Images (Jon's policy: free Docker Hardened Image > Alpine > OSS): both stages are DHI.
FROM dhi.io/node:24-alpine3.22-dev AS build
WORKDIR /app
COPY src/package.json src/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY src/ ./
# Public build-time settings (the publishable key is meant for browsers; RLS protects the data).
ARG VITE_SUPABASE_URL
ARG VITE_SB_PUBLISHABLE_KEY
ARG VITE_ATTACHMENTS_BUCKET=attachments
ARG VITE_IS_DEMO=false
ARG VITE_INBOUND_EMAIL=
ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL VITE_SB_PUBLISHABLE_KEY=$VITE_SB_PUBLISHABLE_KEY \
    VITE_ATTACHMENTS_BUCKET=$VITE_ATTACHMENTS_BUCKET VITE_IS_DEMO=$VITE_IS_DEMO VITE_INBOUND_EMAIL=$VITE_INBOUND_EMAIL
# Upstream's stats plugin tries to open a browser; switch it off (fail if upstream changed).
RUN rm -f .env .env.* \
 && grep -q 'open: process.env.NODE_ENV !== "CI"' vite.config.ts \
 && sed -i 's/open: process.env.NODE_ENV !== "CI"/open: false/' vite.config.ts \
 && NODE_ENV=production npx vite build \
 && rm -f dist/stats.html

FROM dhi.io/nginx:1-alpine3.22
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080
