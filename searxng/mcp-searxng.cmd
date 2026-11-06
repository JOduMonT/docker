@echo off
rem Starts the SearXNG MCP server (stdio) against the local SearXNG container.
set SEARXNG_URL=http://localhost:8888
npx -y mcp-searxng@2.10.0
