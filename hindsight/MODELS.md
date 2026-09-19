## Divid to Conquere
### reflect and consolidation require the most reasoning.
They must resolve contradictions, deduplicate overlapping facts, and synthesize complex answers while following your bank's mission and directives.
- Use DeepSeek V4 Pro for these.

### retain requires minimal reasoning.
It simply parses raw text into structured facts.
- Use DeepSeek V4 Flash for this to keep ingestion fast and cheap.

Set DeepSeek V4 Flash as your global default. Then override the model specifically for the heavier operations using these environment variables.

### DeepSeek Version
```yaml
HINDSIGHT_API_LLM_PROVIDER: deepseek
HINDSIGHT_API_LLM_MODEL: deepseek-v4-flash
HINDSIGHT_API_REFLECT_LLM_MODEL: deepseek-v4-pro
HINDSIGHT_API_CONSOLIDATION_LLM_MODEL: deepseek-v4-pro
```

### Claude Code Version
```yaml
HINDSIGHT_API_LLM_PROVIDER: claude-code
HINDSIGHT_API_LLM_MODEL: claude-haiku-4-5
HINDSIGHT_API_RETAIN_LLM_MODEL: claude-haiku-4-5
HINDSIGHT_API_REFLECT_LLM_MODEL: claude-sonnet-5
HINDSIGHT_API_CONSOLIDATION_LLM_MODEL: claude-sonnet-5
```

### Mix Version
```yaml
# Global & Retain (Uses your Claude subscription)
HINDSIGHT_API_LLM_PROVIDER: claude-code
HINDSIGHT_API_LLM_MODEL: claude-haiku-4-5
HINDSIGHT_API_RETAIN_LLM_PROVIDER: claude-code
HINDSIGHT_API_RETAIN_LLM_MODEL: claude-haiku-4-5

# Reflect & Mental Model Refresh (Routes to a cheaper API)
HINDSIGHT_API_REFLECT_LLM_PROVIDER: deepseek
HINDSIGHT_API_REFLECT_LLM_API_KEY: sk-your-deepseek-api-key
HINDSIGHT_API_REFLECT_LLM_MODEL: deepseek-v4-flash
```
