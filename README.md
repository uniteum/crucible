# crucible

Shared Foundry configuration and deployment scripts for Uniteum repos, consumed
as a git submodule.

## Bitsy

Crucible is designed to simplify the process of creating
[Bitsy](https://uniteum.one/bitsy/) contracts by factoring out common workflow
elements — shared compiler settings, deterministic deployment via
`ProtoScript`, reusable test infrastructure, and shared AI agent
rules so that Claude Code and other agents work consistently across
all Uniteum repos.

Not every contract deployed from a crucible-based repo is Bitsy.
Protocol primitives — the contracts that hold user funds and define
invariant math — are Bitsy. Convenience contracts that wrap or
batch-call those primitives are not. For example, `SolidFactory`
is deployed on-chain but takes a constructor argument and acts as
a multi-call wrapper around `Solid.make` and `Solid.buy`. It is
useful, but it is not a protocol primitive — it has no invariant
of its own, and users don't need to trust it the way they trust
the underlying Solid contract.

The boundary: if a contract defines an invariant that user funds
depend on, it should be Bitsy. If it exists to make Bitsy contracts
easier to use, it doesn't need to be.

---

## New repo setup

Follow these steps in order from the root of a new `uniteum/*` repo.

### 1. Install Foundry dependencies

```bash
forge install foundry-rs/forge-std
git submodule add git@github.com:uniteum/crucible.git lib/crucible
```

### 2. Smelt the repo

The `smelt.sh` script copies all shared crucible files into the repo.

```bash
bash lib/crucible/.claude/skills/smelt/smelt.sh
```

See the [Files](#files) table below for what gets copied. Run `smelt.sh`
again any time you want to refresh the copies from the submodule — it
overwrites existing copies in place and replaces any legacy symlinks
pointing into `lib/crucible/` with real files.

Inside Claude Code, invoke `/smelt` to run the same workflow with
additional checks.

### 3. Create remappings.txt

```
forge-std/=lib/forge-std/src/
crucible/=lib/crucible/
```

Add additional lines for any other submodule dependencies your repo uses (e.g.
`mylib/=lib/mylib/`).

### 4. Create your source directories

```bash
mkdir src test script
```

### 5. Verify

```bash
forge build
```

Your repo is ready. The resulting structure should look like this:

```
repo/
├── foundry.toml             (copied from lib/crucible/foundry.toml)
├── .vscode/settings.json    (copied)
├── .gitignore               (copied, repo may extend)
├── remappings.txt           (per-repo)
├── .mcp.json                (copied)
├── .claude/
│   ├── settings.json        (copied)
│   ├── rules/
│   │   ├── always.md        (copied)
│   │   ├── lint.md          (copied)
│   │   ├── solidity.md      (copied)
│   │   ├── crucible-tests.md (copied)
│   │   └── submodule.md     (copied)
│   └── skills/
│       ├── bitsify/SKILL.md (copied)
│       └── smelt/           (copied — SKILL.md and smelt.sh)
├── lib/
│   ├── forge-std/
│   └── crucible/              ← this submodule
├── src/
├── test/
└── script/
```

---

## Files

The **authoritative list** of files copied into consumer repos is the
`FILES` array in [`.claude/skills/smelt/smelt.sh`](.claude/skills/smelt/smelt.sh).
The table below is a human-readable summary.

| Submodule file | Copied to (same path in consumer) | Purpose |
|---|---|---|
| `foundry.toml` | `foundry.toml` | Foundry compiler, profiles, and RPC config |
| `.vscode/settings.json` | `.vscode/settings.json` | Shared VS Code workspace settings |
| `.mcp.json` | `.mcp.json` | MCP server configuration (Etherscan) |
| `.claude/settings.json` | `.claude/settings.json` | Claude Code permissions (Foundry tool access) |
| `.claude/rules/always.md` | `.claude/rules/always.md` | Claude Code rules applied to all files |
| `.claude/rules/lint.md` | `.claude/rules/lint.md` | Claude Code rules for Solidity linting |
| `.claude/rules/solidity.md` | `.claude/rules/solidity.md` | Claude Code rules for Solidity files |
| `.claude/rules/crucible-tests.md` | `.claude/rules/crucible-tests.md` | Claude Code rules for test files |
| `.claude/rules/submodule.md` | `.claude/rules/submodule.md` | Claude Code rules for submodule maintenance |
| `.claude/skills/bitsify/SKILL.md` | `.claude/skills/bitsify/SKILL.md` | `/bitsify` skill — convert a contract to the Bitsy pattern |
| `.claude/skills/smelt/SKILL.md` | `.claude/skills/smelt/SKILL.md` | `/smelt` skill — apply the crucible pattern |
| `.claude/skills/smelt/smelt.sh` | `.claude/skills/smelt/smelt.sh` | Copy script invoked by `/smelt` |

Files handled specially:

| File | How it's consumed |
|---|---|
| `script/Proto.s.sol` | Imported via `remappings.txt` (`crucible/=lib/crucible/`) |
| `.gitignore` | Copied on first smelt only — repos may add their own patterns |
| `AGENTS.md` | AI instructions, internal to this submodule |

### Why copies instead of symlinks

Earlier repos symlinked these files straight into `lib/crucible/`, which
kept them in sync automatically but made the repo harder to read, broke
on systems without symlink support, and surprised new contributors who
edited a "local" file and found they'd changed the submodule. Copies are
plain files; `smelt.sh` is the refresh mechanism.

When smelting a legacy repo, `smelt.sh` deletes each symlink before
writing the copy, so the conversion happens in one pass.

---

## MCP Servers

Crucible ships an `.mcp.json` that configures the
[Etherscan MCP](https://docs.etherscan.io/mcp) server. This gives Claude
Code direct access to on-chain data across 60+ EVM chains: verified contract
source, ABIs, transaction history, balances, and more.

### Setup

1. **Get an API key** from [etherscan.io/myapikey](https://etherscan.io/myapikey)
   (free tier is sufficient — 5 calls/sec).

2. **Export the key** in your shell profile (`.bashrc`, `.zshrc`, etc.):

   ```bash
   export ETHERSCAN_API_KEY="your-key-here"
   ```

3. **Symlink** `.mcp.json` into your repo root (already included in the
   [New repo setup](#new-repo-setup) steps above):

   ```bash
   ln -s lib/crucible/.mcp.json .mcp.json
   ```

4. **Restart Claude Code** — it will detect the MCP server and prompt you
   to approve it on first use.

### What you can do with it

- Fetch verified source code for any contract on any Etherscan-supported chain
- Pull ABIs to generate Solidity interfaces
- Inspect deployer addresses and constructor arguments
- Check token balances, transaction history, and internal transactions
- Compare deployed bytecode against local builds
- Monitor gas prices

### Access tiers

Your Etherscan API key tier determines rate limits. The free tier (5 calls/sec)
is enough for interactive use. If you hit rate limits during heavy analysis,
consider upgrading at [etherscan.io/apis](https://etherscan.io/apis).

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
