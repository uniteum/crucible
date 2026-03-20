# config

Shared Foundry configuration for Uniteum repos, consumed as a git submodule.

## What's in here

- `foundry.toml` — canonical Foundry config shared across all `uniteum/*` repos

## Usage

### Adding to a repo

```bash
git submodule add git@github.com:uniteum/config.git config
echo "FOUNDRY_CONFIG=config/foundry.toml" >> .env
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
git submodule update --remote config
```

## RPC endpoints

`foundry.toml` defines RPC endpoints using environment variable interpolation:

```toml
[rpc_endpoints]
mainnet = "${RPC_MAINNET}"
sepolia = "${RPC_SEPOLIA}"
```

The actual URLs are never stored here. Each repo's `.env` contains only the
`FOUNDRY_CONFIG` pointer (safe to commit); the `RPC_*` variables are expected
to arrive via whatever secret delivery mechanism you use (shell profile, CI
secrets manager, 1Password CLI, etc.).

## Per-repo overrides

If a repo needs to diverge from the shared config, use `FOUNDRY_*` environment
variables to override individual settings without forking `foundry.toml`:

```bash
# .env (committed, repo-specific)
FOUNDRY_CONFIG=config/foundry.toml
FOUNDRY_OUT=out/custom
```

See the [Foundry docs](https://book.getfoundry.sh/reference/config/overview)
for the full list of supported `FOUNDRY_*` env vars.
