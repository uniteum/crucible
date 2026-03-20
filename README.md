# solidity

Shared Foundry configuration for Uniteum repos, consumed as a git submodule.

## What's in here

- `foundry.toml` — canonical Foundry config shared across all `uniteum/*` repos
- `.vscode/` — shared VS Code workspace settings
- `.claude/rules/solidity.md` — Claude Code rules for Solidity development
- `.claude/settings.json` — shared Claude Code permissions (Foundry tool access)
- `AGENTS.md` — AI instructions for this repo (`CLAUDE.md` symlinks here)

### Compiler settings

Solc 0.8.30, Cancun EVM, optimizer enabled (200 runs, via IR).

### Profiles

| Profile   | Invariant runs | Depth |
|-----------|---------------|-------|
| `default` | 256           | 500   |
| `ci`      | 512           | 1,000 |
| `quick`   | 32            | 64    |
| `deep`    | 1,024         | 2,000 |

Select a profile with `FOUNDRY_PROFILE=ci forge test`.

### RPC endpoints

Endpoints are keyed by chain ID and point to free public RPCs. No secrets or
environment variables required for standard usage.

## Usage

### Adding to a repo

```bash
git submodule add git@github.com:uniteum/solidity.git solidity
ln -s solidity/foundry.toml foundry.toml
ln -s solidity/.vscode .vscode
mkdir -p .claude/rules
ln -s ../solidity/.claude/settings.json .claude/settings.json
ln -s ../../solidity/.claude/rules/solidity.md .claude/rules/solidity.md
```

### Cloning a repo that uses this submodule

```bash
git clone --recurse-submodules git@github.com:uniteum/<repo>.git
```

Or if you already cloned without `--recurse-submodules`:

```bash
git submodule update --init
```

### Updating to the latest config

```bash
git submodule update --remote solidity
```

## Per-repo overrides

If a repo needs to diverge from the shared config, use `FOUNDRY_*` environment
variables to override individual settings without forking `foundry.toml`:

```bash
# .env (repo-specific)
FOUNDRY_OUT=out/custom
```

See the [Foundry docs](https://book.getfoundry.sh/reference/config/overview)
for the full list of supported `FOUNDRY_*` env vars.
