# Temporary public demo link for local Appsmith (Cloudflare quick tunnel).
# No Cloudflare account or domain needed. Prints a random https://*.trycloudflare.com URL.
# The link lives only while this window runs: press Ctrl+C after the demo to close it.
# Exposes the whole Appsmith (login page too); public sign-up is disabled in .env.local.
$cf = (Get-Command cloudflared -ErrorAction SilentlyContinue).Source
if (-not $cf) { $cf = "C:\Program Files (x86)\cloudflared\cloudflared.exe" }
& $cf tunnel --no-autoupdate --url http://127.0.0.1:3000
