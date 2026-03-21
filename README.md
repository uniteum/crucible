# crucible

Shared Foundry configuration and deployment scripts for Uniteum repos, consumed
as a git submodule.

## New repo setup

Follow these steps in order from the root of a new `uniteum/*` repo.

### 1. Install Foundry dependencies

```bash
forge install foundry-rs/forge-std
git submodule add git@github.com:uniteum/crucible.git lib/crucible
```

### 2. Create symlinks

These keep your repo in sync with the shared config. See the
[Symlinks](#symlinks) table for what each file does.

```bash
ln -s lib/crucible/foundry.toml foundry.toml
ln -s lib/crucible/.vscode .vscode
mkdir -p .claude/rules
ln -s ../lib/crucible/.claude/settings.json .claude/settings.json
ln -s ../../lib/crucible/.claude/rules/solidity.md .claude/rules/solidity.md
```

### 3. Copy the .gitignore

```bash
cp lib/crucible/.gitignore .gitignore
```

The `.gitignore` is copied rather than symlinked so repos can add their own
patterns. Edit as needed.

### 4. Create remappings.txt

```
forge-std/=lib/forge-std/src/
crucible/=lib/crucible/
```

Add additional lines for any other submodule dependencies your repo uses (e.g.
`mylib/=lib/mylib/`).

### 5. Create your source directories

```bash
mkdir src test script
```

### 6. Verify

```bash
forge build
```

Your repo is ready. The resulting structure should look like this:

```
repo/
├── foundry.toml           → lib/crucible/foundry.toml
├── .vscode                → lib/crucible/.vscode
├── .gitignore               (copied from lib/crucible/.gitignore)
├── remappings.txt           (per-repo)
├── .claude/
│   ├── settings.json      → ../lib/crucible/.claude/settings.json
│   └── rules/
│       └── solidity.md    → ../../lib/crucible/.claude/rules/solidity.md
├── lib/
│   ├── forge-std/
│   └── crucible/            ← this submodule
├── src/
├── test/
└── script/
```

---

## Symlinks

This table is the **single source of truth** for what gets symlinked from this
submodule into consumer repos.

| Submodule file | Symlink in consumer repo | Purpose |
|---|---|---|
| `foundry.toml` | `foundry.toml` | Foundry compiler, profiles, and RPC config |
| `.vscode/` | `.vscode` | Shared VS Code workspace settings |
| `.claude/settings.json` | `.claude/settings.json` | Claude Code permissions (Foundry tool access) |
| `.claude/rules/solidity.md` | `.claude/rules/solidity.md` | Claude Code rules for Solidity files |

Files **not** symlinked:

| File | How it's consumed |
|---|---|
| `script/Proto.s.sol` | Imported via `remappings.txt` (`crucible/=lib/crucible/`) |
| `AGENTS.md` | AI instructions, internal to this submodule |
| `.gitignore` | Copied (not symlinked) — repos may add their own patterns |

---

## Reference

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

### Per-repo overrides

If a repo needs to diverge from the shared config, use `FOUNDRY_*` environment
variables to override individual settings without forking `foundry.toml`:

```bash
# .env (repo-specific)
FOUNDRY_OUT=out/custom
```

See the [Foundry docs](https://book.getfoundry.sh/reference/config/overview)
for the full list of supported `FOUNDRY_*` env vars.

---

## ProtoScript

`ProtoScript` is an abstract Forge script that deploys a contract via
[Nick's CREATE2 deployer](https://github.com/Arachnid/deterministic-deployment-proxy)
(`0x4e59b44847b379578588920cA78FbF26c0B4956C`) with salt `0x0`. This gives every
protofactory contract a deterministic address that is the same on every chain.

Subclasses override two functions:

```solidity
function name() internal pure override returns (string memory);
function creationCode() internal pure override returns (bytes memory);
```

### Example

```solidity
import {MyContract} from "../src/MyContract.sol";
import {ProtoScript} from "crucible/script/Proto.s.sol";

contract MyContractProto is ProtoScript {
    function name() internal pure override returns (string memory) {
        return "MyContractProto";
    }

    function creationCode() internal pure override returns (bytes memory) {
        return type(MyContract).creationCode;
    }
}
```

### Environment variables

ProtoScript requires two environment variables:

| Variable | Purpose | Example |
|----------|---------|---------|
| `env`    | Deployment environment (`test` or `prod`) | `prod` |
| `chain`  | Numerical chain ID | `1` |

### Running a deployment

```bash
env=prod chain=42161 forge script script/MyContractProto.s.sol \
    -f $chain --private-key $tx_key --broadcast
```

### The `io/` directory

Each deployment writes the predicted contract address to a JSON file under:

```
io/<env>/<chain>/<file>.json
```

where `env` is `test` or `prod` and `chain` is the numerical chain ID. Test
chains go under `test/`, production chains under `prod/`:

```
io/
├── prod/
│   ├── 1/                        # Ethereum mainnet
│   │   └── MyContractProto.json
│   └── 42161/                    # Arbitrum One
│       └── MyContractProto.json
└── test/
    └── 11155111/                 # Sepolia
        └── MyContractProto.json
```

This provides a persistent, per-environment, per-chain record of deployed
addresses that scripts and tests can read back. The `io/` directory is local to
each consumer repo (not inside the crucible submodule). `foundry.toml` already
grants read-write `fs_permissions` to `./io/`.

---

## Maintenance

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
git submodule update --remote lib/crucible
```
