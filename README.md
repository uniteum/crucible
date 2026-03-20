# solidity

Shared Foundry configuration and deployment scripts for Uniteum repos, consumed
as a git submodule.

## What's in here

- `foundry.toml` — canonical Foundry config shared across all `uniteum/*` repos
- `script/Proto.s.sol` — base deployment script for CREATE2 protofactory contracts
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
import {ProtoScript} from "solidity/script/Proto.s.sol";

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
each consumer repo (not inside the solidity submodule). `foundry.toml` already
grants read-write `fs_permissions` to `./io/`.

## Usage

### Adding to a repo

```bash
git submodule add git@github.com:uniteum/solidity.git lib/solidity
ln -s lib/solidity/foundry.toml foundry.toml
ln -s lib/solidity/.vscode .vscode
mkdir -p .claude/rules
ln -s ../lib/solidity/.claude/settings.json .claude/settings.json
ln -s ../../lib/solidity/.claude/rules/solidity.md .claude/rules/solidity.md
```

Add a remapping for the solidity submodule so Forge can resolve imports from it:

```
# remappings.txt
solidity/=lib/solidity/
```

Each repo's `remappings.txt` will also include entries for its own dependencies
(e.g. `forge-std/=lib/forge-std/src/`). The `solidity/=lib/solidity/` remapping is
the only one needed to use `ProtoScript` and any future shared scripts.

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
git submodule update --remote lib/solidity
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
