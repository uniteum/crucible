# Deployment

> **Status: as-built reference.** This describes the deployment
> pipeline as it is actually implemented in
> [`script/`](../script/) and consumed by `lepton`, `locale`,
> `unispring`, and `uniteum`. The legacy Forge helper
> [`script/Proto.s.sol`](../script/Proto.s.sol) is superseded by this
> pipeline and is retained only for the two deferred Neutrino proto
> scripts in `unispring` (`NeutrinoChannelProto.s.sol`,
> `NeutrinoSourceProto.s.sol`); see [Status](#status) and the
> [`predict` skill](../.claude/skills/predict/SKILL.md).

## Invariant

Deployment inputs are predicted, committed to source control, and only
then broadcast. The `io/` directory of a consumer repo is the
deployment manifest: once committed, any contributor with a funded key
can deploy any subset of the dependency graph to a new chain in a
single command, with no intermediate computation.

This invariant has three consequences:

1. **All deployment artifacts are chain-independent.** Predicted
   addresses are identical on every chain by construction (CREATE2 with
   the same deployer, salt, and initcode produces the same address).
2. **No per-chain state lives in the repo.** Whether a contract has
   been deployed to a given chain is recorded on the chain itself, read
   via `cast code <addr>`. Re-running deploy after a partial failure
   is safe and idempotent.
3. **Mining and prediction are offline.** Only the broadcast step
   touches the network for writes; only the existence check touches
   it for reads.

## Two patterns

A **prototype** is a contract that is both a factory and an
implementation. It inherits `Prototype` (from `uniteum/proto`), which
exposes `make(bytes args, uint256 variant)` to mint EIP-1167 proxies
keyed to itself. Prototypes are deployed via Nick's deterministic
deployer (`0x4e59b44847b379578588920cA78FbF26c0B4956C`).

```
prototypeAddr = create2(Nick, salt, keccak(creationCode ‖ abiEncode(args)))
```

`proto_predict` builds the initcode as `forge inspect <C> bytecode`
concatenated with `cast abi-encode <constructorSig> <args>`.

A **clone** is an EIP-1167 proxy minted by a prototype's `make(...)`
call. The prototype hashes the `bytes` args blob and XORs the result
with the user-supplied variant to form the CREATE2 salt; the initcode
is the 55-byte EIP-1167 proxy stub keyed to the prototype.

```
args_bytes = cast abi-encode "f(<argstype>)" <values…>   # the bytes Prototype.made receives
argshash   = keccak(args_bytes)
salt       = argshash ^ variant
cloneAddr  = create2(prototype, salt, keccak(eip1167(prototype)))
```

`args_bytes` is the content of `make`'s `bytes` parameter, and
`argshash` is hashed from it **directly** — there is no second
`abi.encode` wrapper. (Earlier tooling double-encoded; that was
removed so `argshash` matches what `Prototype.made(bytes,uint256)`
actually computes.) The EIP-1167 stub is:

```
0x3d602d80600a3d3981f3363d3d373d3d3d363d73<deployer>5af43d82803e903d91602b57fd5bf3
```

Vanity addresses are produced by mining `salt` (prototype) or `variant`
(clone) until the resulting address satisfies a target mask — see
[Salt mining](#salt-mining).

## Artifacts

For each predicted address, two or three files are written under
`io/<contract>/`:

| File          | Contents                                              | Prototype | Clone |
|---------------|-------------------------------------------------------|-----------|-------|
| `<addr>.txt`  | Raw transaction input data sent to `deployer`         | yes       | yes   |
| `<addr>.yml`  | Metadata: kind, deployer, hashes, mining inputs, args | yes       | yes   |
| `<addr>.json` | Etherscan standard-input verification JSON            | yes       | no    |

Clones do not need `<addr>.json`: an EIP-1167 proxy is verified by
Etherscan's proxy-detection mechanism, which keys to the prototype's
already-verified source.

### `<addr>.txt`

For a **prototype**, the file is `salt ‖ initcode` — the calldata
Nick's deployer expects. For a **clone**, the file is
`cast calldata "make(bytes,uint256)" <args_bytes> <variant>` — the
call sent to the prototype's address.

The `.txt` file is exactly what `deploy.sh` broadcasts; no further
computation happens at deploy time.

### `<addr>.yml`

A **prototype** yml records everything needed to reproduce the
prediction and verify the source:

```yaml
contract: Fountain                                              # forge inspect name
kind: prototype
deployer: "0x4e59b44847b379578588920cA78FbF26c0B4956C"          # Nick
initcodehash: "0x..."
salt: "0x000000000000000000000000000000000000000000000000000000000236b9e6"
compilerversion: "v0.8.34+commit...."                           # captured at predict time
license: "MIT"                                                  # SPDX id from src
mask: "0xfff000000000000000000000000000000000ffff"              # present only if vanity-mined
target: "0xf00000000000000000000000000000000000e090"            # present only if vanity-mined
args:                                                           # raw constructor values, in order
  - "0x9891e323517761F525e55817F1b3fa2C52620b78"
  - "0xB001b0342E8bf106c8DdB2f858a8cA15A171e300"
home: "0xF00c0C30CE13f01c77C1F8d60Fc1146014B4E090"              # the predicted address
```

A **clone** yml records the factory inputs instead. `deployer` is the
prototype's address, `variant` is the user-supplied value the prototype
XORs with `argshash` to form the CREATE2 salt, and `argshash` /
`argstype` make the prediction reproducible:

```yaml
contract: PoolManagerLookup
kind: clone
deployer: "0x..."                                               # the prototype that make()s it
initcodehash: "0x..."                                           # keccak(eip1167(prototype))
argstype: "(uint256,address)[]"                                 # types between make()'s parens
argshash: "0x..."                                               # keccak(args_bytes)
mask: "0x..."                                                   # present only if vanity-mined
target: "0x..."                                                 # present only if vanity-mined
variant: "0x...01e833d4bb"
home: "0x..."
```

`compilerversion` and `license` are captured at predict time so
`verify.sh` can submit the source even if `foundry.toml` later changes
solc. `mask`/`target` are recorded so re-mining on another machine
produces the same salt/variant deterministically — if it doesn't,
something has drifted.

The `args` block is documentation and is also walked by `deploy.sh` to
recurse into constructor-arg dependencies (see
[Deploy algorithm](#deploy-algorithm)); the `.txt` already encodes
everything needed to broadcast.

## Layout

```
lib/crucible/script/
  lib.sh       shared CREATE2 formulas + mine_clone; cd's nowhere
  proto.sh     proto_predict — prototype prediction; cd's to repo root
  clone.sh     clone_predict — clone prediction; sources lib.sh; cd's to repo root
  deploy.sh    broadcasts committed .txt files to their deployers
  verify.sh    submits a committed .json to Etherscan

<consumer-repo>/io/
  Fountain/
    Fountain.sh   prediction recipe — sources proto.sh, calls proto_predict
    <addr>.txt
    <addr>.yml
    <addr>.json
  PoolManagerLookup/
    PoolManagerLookup.sh   prediction recipe — sources clone.sh, calls clone_predict
    <addr>.txt
    <addr>.yml
```

> **Known nit:** [`proto.sh`](../script/proto.sh) still carries a
> stale `# crucible/script/lib.sh` header comment from before the
> shared formulas were factored into a separate `lib.sh`. It is
> cosmetic — consumers source `proto.sh` by name.

Each `<contract>.sh` is the prediction recipe for that contract,
co-located with the artifacts it produces. Inputs (mined salt/variant,
factory and constructor-arg addresses, the contract name) are written
**inline in the script itself**, not pulled from `.env`. A real
example, [`unispring/io/Fountain/Fountain.sh`](../../unispring/io/Fountain/Fountain.sh):

```bash
source "$(git rev-parse --show-toplevel)/lib/crucible/script/proto.sh"

PoolManagerLookup=0xB001b0342E8bf106c8DdB2f858a8cA15A171e300
owner=0x9891e323517761F525e55817F1b3fa2C52620b78
mask=0xfff000000000000000000000000000000000ffff
target=0xf00000000000000000000000000000000000e090
proto_predict Fountain 0x...0236b9e6 \
    "constructor(address,address)" "$owner" "$PoolManagerLookup"
```

Re-running the script regenerates the artifacts from current inputs
plus the contract source (bytecode via `forge inspect`). There are
**no per-repo orchestration scripts** — the three predict helpers plus
`deploy.sh`/`verify.sh` in crucible are the entire deployment surface
for every consumer repo.

### Predict helpers

```
proto_predict <ContractName> <salt> [<constructorSig> <arg>...]
clone_predict <CloneName> <deployer> <argsType> <argsValue>... <variant>
```

`proto_predict` writes `<addr>.{txt,yml,json}`; `clone_predict` writes
`<addr>.{txt,yml}` (no `.json`). Both print `<Name>=<addr>` on stdout
and `cd` to the repo root on source so `io/<contract>/...` resolves
regardless of the caller's cwd. `clone_predict` sources `lib.sh` for
the shared `clone_proxy_initcode` / `clone_args_bytes` formulas so
prediction and mining cannot drift apart.

## Deploy algorithm

```
bash lib/crucible/script/deploy.sh [-b|--broadcast] [<wallet-flags>] <chain> <addr>
```

Run from a consumer repo's root. **Default is dry-run**: the dep chain
is walked and printed in order without sending anything. Pass `-b` /
`--broadcast` to actually broadcast. In broadcast mode the wallet
defaults to `--private-key "$tx_key"`; any cast wallet flag
(`--account`, `--keystore`, `--ledger`, `--mnemonic …`, …) passed
before the positional args overrides that.

`<chain>` is an `[rpc_endpoints]` key from `foundry.toml` or an RPC
URL. `<addr>` is the target; its `<addr>.yml` is located by indexing
every `io/*/<addr>.yml` in this repo **and in every sibling repo's
`io/`** (`../*/io`, overridable via `io_root`). This lets a repo
depend on contracts whose artifacts live in another repo without
vendoring it as a submodule.

```
deploy(addr):
    if addr already visited this run:    return        # VISITED memo
    if cast code addr on chain != 0x:    return        # already deployed
    yml = YML_PATH[addr]                                # error if no io entry
    deploy(yml.deployer)                                # ensure the factory exists
    for argAddr in yml.args having an io entry:
        deploy(argAddr)                                 # ensure runtime deps exist
    broadcast yml's <addr>.txt to yml.deployer          # cast send (broadcast mode only)
```

`cast code` is the source of truth, so partial-failure recovery is
automatic: rerun and the script picks up where it left off.
Constructor-arg addresses with no io entry (external contracts like a
Uniswap V4 PoolManager or USDC) are silently skipped. No cycle
detection is needed — clones depend on prototypes minted before them,
so the graph is a DAG by construction. Nick's deployer is not
special-cased: it bottoms out the recursion because it already has
code on every chain we target.

### Chains without Nick

A handful of niche or new chains do not yet have Nick's deployer at
`0x4e59b44...`. There the recursion fails at the first prototype
because Nick himself has no code and no io entry to bring him up. The
standard fix is to fund the pre-funded EOA
`0x3fab184622dc19b6109349b94811493bf2a45362` with a little native gas
and broadcast Arachnid's canonical pre-signed transaction. Doing this
through the same recursive step (e.g. a `kind: presigned` io entry
whose `.txt` is the raw transaction) is a possible future iteration;
for now, operators bootstrap Nick manually on such chains before
running `deploy.sh`.

## Verification

```
ETHERSCAN_API_KEY=... bash lib/crucible/script/verify.sh <chain> <addr>
```

`verify.sh` locates `<addr>.yml` (local `io/` first, then sibling
repos under `io_root`) and submits the **committed** `<addr>.json` —
the Etherscan standard-input bundle captured at predict time by
`forge verify-contract --show-standard-json-input` — to Etherscan's
unified **v2 API** (`https://api.etherscan.io/v2/api?chainid=<chain>`),
then polls `checkverifystatus` until it passes or times out.

It intentionally does **not** call `forge verify-contract` at this
stage: forge would regenerate the standard input from current source +
`foundry.toml`, which can drift from what was actually deployed
(different solc, edited source). Shipping the captured `.json`
guarantees byte-identical input. The SPDX identifier recorded in the
yml is mapped to Etherscan's numeric `licenseType` (unrecognized
licenses submit as "None", which Etherscan accepts).

A single `ETHERSCAN_API_KEY` covers every chain — the v2 API selects
the chain via the `chainid` query parameter, so there is no per-chain
endpoint table or verifier config file to maintain.

### Clones

Clones have no `<addr>.json`. When `verify.sh` is pointed at a
`kind: clone` entry it does not call any proxy-verification endpoint;
it prints the deployer (prototype) address and instructs you to verify
that instead. Once the prototype's source is verified, Etherscan
auto-detects each EIP-1167 proxy and inherits the prototype's source.

## Salt mining

Salt mining is upstream of prediction: it produces the salt (for
prototypes) or variant (for clones) that gets written into the
per-contract predict script and consumed on every chain. Mining is not
part of normal deployment — once a salt/variant is chosen it is reused
everywhere.

### Tool

[saltminer](https://github.com/uniteum/saltminer) is the GPU-based
miner. Inputs:

| Flag              | Prototype                          | Clone                              |
|-------------------|------------------------------------|------------------------------------|
| `--deployer`      | Nick (`0x4e59b44...`)              | the Bitsy prototype address        |
| `--initcodehash`  | `keccak(creationCode ‖ args)`      | `keccak(eip1167(prototype))`       |
| `--argshash`      | omitted                            | `keccak(args_bytes)`               |
| `--mask`          | bits the address must match        | same                               |
| `--target`        | target value under the mask        | same                               |

For prototypes, saltminer varies the salt directly. For clones it
varies a variant; the factory's actual salt is `argshash ^ variant`,
but the value committed and passed to `make(args, variant)` is the
variant itself.

### `mine_clone` helper

[`lib.sh`](../script/lib.sh) provides `clone_proxy_initcode`,
`clone_args_bytes`, and `mine_clone <deployer> <argstype>
<argsValue>...`. `mine_clone` reads the target pattern from the
`mask`/`target` env vars — the same convention `clone_predict` captures
into the yml — computes the init-code and args hashes from the shared
formulas, and shells out to `saltminer`, which prints the matching
variant and resulting address. There is no `mine_proto` helper:
prototype salts are mined by invoking `saltminer` directly with the
proto's initcode hash.

### The Bitsy clone convention

Clones produced by Bitsy factories follow a fixed convention:

```solidity
function make(/* args */, uint256 variant) external returns (address);
function made(/* args */, uint256 variant) external view returns (bool, address, bytes32);
```

Both compute `salt = keccak(args_bytes) ^ bytes32(variant)` internally,
and `make()` calls `Clones.cloneDeterministic(proto, salt, 0)`. This
shape is what lets `saltminer` vary `variant` without re-encoding
`args` each iteration. Bitsy contracts that don't follow this
convention cannot be vanity-mined with `saltminer`. See
[crucible/.claude/skills/bitsify/SKILL.md](../.claude/skills/bitsify/SKILL.md)
for the full pattern.

## Status

The pipeline is implemented and in use. `lepton`, `locale`,
`unispring`, and `uniteum` deploy their prototypes and clones through
`io/<contract>/<contract>.sh` + `deploy.sh`/`verify.sh`, and the
[`predict` skill](../.claude/skills/predict/SKILL.md) generates new
recipes.

The legacy Forge helper [`script/Proto.s.sol`](../script/Proto.s.sol)
(`ProtoScript`) is superseded. It is retained **only** because
`unispring`'s two deferred Neutrino proto scripts
(`NeutrinoChannelProto.s.sol`, `NeutrinoSourceProto.s.sol`) still
import it; no other consumer does. When those two migrate to
`proto_predict`, `Proto.s.sol` and the `## ProtoScript` section of
[`README.md`](../README.md) can be removed outright.
