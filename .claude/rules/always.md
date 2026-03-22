---
paths:
  - "**"
---

# General Rules

## Bash Tool Usage

- Avoid compound statements (`; && |`). Use separate, parallel Bash tool calls instead so each command can be individually matched by permission rules.
- Only use compound statements when there's a genuine dependency that can't be expressed otherwise.
