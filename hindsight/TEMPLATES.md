## Research Assistant — deploy that one, and only that one.
Why it, over the alternatives. Its own reflect_mission reads:
- "monitors sources, writes briefings and digests, and maintains a second brain."

### That's your notes/ideas/blog bank verbatim.
It ships three mental models
1. Interests & Focus
2. Knowledge Base
3. Sources & Reliability
- plus a "learn from what's ignored" directive that uses what you skip to filter future curation.
- Dispositions are skepticism 4 / empathy 2: a thinking partner that pushes back, not a warm helper.

## Personal Assistant
is the near-miss — but it's routines, schedule, people, commitments. That's task management.

## For vibecoding
don't deploy a template at all. The Coding Agent template is for a bank you drive yourself. The coding-agents plugin does this automatically: one bank per repo (coding-agent::{gitProject}), and with manageBankConfig: true it seeds the missions, the five retain strategies and the knowledge label group itself. Hand-importing on top just duplicates that. 

## Self-Hosted
The coding side is a separate install: `npx @vectorize-io/hindsight-coding-agents install claude-code --server self-hosted --api-url http://localhost:8888`

The `--server` flag matters. Default is Hindsight Cloud, a bare install prompts for it, and re-running never re-asks — so a wrong answer there quietly ships your prompts off-machine and sticks.
