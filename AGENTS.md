# AGENTS.md — Shared Solidity Configuration

> AI instructions for the `uniteum/solidity` submodule.

## What This Repo Is

This is a **shared configuration submodule** consumed by all `uniteum/*` Solidity repos.
It is not a standalone project — it has no `src/`, no contracts, no tests.

Contents:
- `foundry.toml` — canonical Foundry config
- `.vscode/` — shared VS Code workspace settings
- `.claude/settings.json` — shared Claude Code permissions
- `.claude/rules/solidity.md` — Claude Code rules for Solidity development
- `.gitignore` — shared ignore patterns

## Symlink Architecture

Consumer repos add this as a git submodule at `solidity/` and symlink files into place:

```
repo/
├── solidity/              ← this submodule
├── foundry.toml           → solidity/foundry.toml
├── .vscode                → solidity/.vscode
├── .claude/
│   ├── settings.json      → ../solidity/.claude/settings.json
│   └── rules/
│       └── solidity.md    → ../../solidity/.claude/rules/solidity.md
└── CLAUDE.md              ← repo-specific (NOT symlinked)
```

### When Adding New Files

When a new file is added to this repo, **ask the user** whether consumer repos
should symlink it. If yes:

1. Add the symlink command to the "Adding to a repo" section in `README.md`
2. Note the relative symlink path (it must work from the consumer repo root)
3. The user will need to create the symlinks in each consumer repo separately

## Editing Guidelines

### foundry.toml

- This is the **single source of truth** for Foundry configuration across all uniteum repos
- Changes here affect every consumer repo on their next `git submodule update`
- Be conservative — prefer per-repo `FOUNDRY_*` env var overrides for repo-specific needs
- Keep RPC endpoints pointing to free public RPCs (no API keys)

### .claude/rules/solidity.md

- These rules apply to all Solidity files in every consumer repo
- Keep rules general — repo-specific rules belong in the consumer repo's own `.claude/` directory
- The `paths` frontmatter controls which files trigger the rules

### .gitignore

- Covers common patterns across Solidity, Node.js, frontend, and deployment artifacts
- Consumer repos can add their own `.gitignore` for repo-specific exclusions

### README.md

- Primary audience: developers adding or updating the submodule in their repos
- Keep the symlink instructions current with the actual repo contents
- Update the "What's in here" list when files are added or removed

## Do Not

- Add contracts, tests, or scripts — this is config only
- Add secrets, API keys, or private RPC endpoints
- Break backward compatibility in foundry.toml without coordinating across consumer repos
- Modify files expecting them to only affect one repo — changes propagate everywhere
