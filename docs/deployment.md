# Deployment

> **Status: design doc, not yet implemented.** This describes the target
> layout for refactoring `unispring/script/*.sh` and equivalent
> deployment scripts across consumer repos. The current
> [`script/Proto.s.sol`](../script/Proto.s.sol) is superseded by this
> design and will be retired once consumers have migrated.

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
implementation: it has a `make(...)` method that mints EIP-1167 proxies
keyed to itself. Prototypes are deployed via Nick's deterministic
deployer (`0x4e59b44847b379578588920cA78FbF26c0B4956C`).

```
prototypeAddr = create2(Nick, salt, keccak(creationCode ‖ abiEncode(args)))
```

A **clone** is an EIP-1167 proxy minted by a prototype's `make(...)`
call. The prototype XORs `keccak(abi.encode(makeArgs))` with the
user-supplied variant to form the CREATE2 salt; the initcode is the
55-byte EIP-1167 proxy stub keyed to the prototype.

```
cloneAddr = create2(prototype, keccak(args) ^ variant, keccak(eip1167(prototype)))
```

Vanity addresses are produced by mining `salt` (prototype) or `variant`
(clone) until the resulting address satisfies a target mask.

## Artifacts

For each predicted address, two or three files are written under
`io/<contract>/`:

| File          | Contents                                         | Prototype | Clone |
|---------------|--------------------------------------------------|-----------|-------|
| `<addr>.txt`  | Raw transaction input data                       | yes       | yes   |
| `<addr>.yml`  | Metadata: deployer, variant, mining inputs, args | yes       | yes   |
| `<addr>.json` | Etherscan standard-input verification JSON       | yes       | no    |

Clones do not need `<addr>.json`: an EIP-1167 proxy is verified by
Etherscan's proxy-detection mechanism, which keys to the prototype's
already-verified source.

### `<addr>.txt`

For a prototype, the file contains `salt ‖ initcode` — the calldata
Nick's deployer expects. For a clone, the file contains the encoded
factory call (e.g. `make(uint256)` selector ‖ variant), to be sent to
the prototype's address.

The `.txt` file is what `deploy.sh` broadcasts. It encodes everything
the deployer needs; no further computation is required at deploy time.

### `<addr>.yml`

```yaml
contract: Fountain          # source contract name (matches forge inspect)
kind: prototype             # or "clone"
deployer: 0x4e59b44847b379578588920cA78FbF26c0B4956C
variant: 0x00000000000000000000000000000000000000000000000000000001c8688910
mask: 0xffffffff00000000000000000000000000000000000000000000000000000000
match: 0xfeedface00000000000000000000000000000000000000000000000000000000
initcodeHash: 0x...
args:
  - name: poolManager
    type: address
    value: 0x...
```

For a clone, `kind: clone`, `deployer` is the prototype's address,
`variant` is the user-supplied input that the prototype XORs with
`argsHash` to form the CREATE2 salt, and an additional `argsHash`
field records `keccak(abi.encode(makeArgs))` for prediction
reproducibility:

```yaml
contract: Fountain
kind: clone
deployer: 0xF0F1d225A78c1EdcD0f5a9E31398Ed0BA3Dee071   # the Fountain prototype
variant: 0x00000000000000000000000000000000000000000000000000000001e833d4bb
mask: 0xffff00000000000000000000000000000000000000000000000000000000ffff
match: 0xfeed000000000000000000000000000000000000000000000000000000000001
argsHash: 0x...
args:
  - name: maker
    type: address
    value: 0xff966FE50802B74B538D2c6311Fc0201014AA294
```

`mask` and `match` are recorded so that re-mining on a different
machine produces the same variant deterministically — if it doesn't,
something has drifted.

The `args` block is documentation only. `deploy.sh` does not read it;
`<addr>.txt` already encodes everything needed to broadcast.

## Layout

```
lib/crucible/script/
  deploy.sh          broadcasts committed .txt files to their deployers
  verify.sh          submits .json files to configured block explorers
  lib.sh             shared bash helpers (proto_predict, clone_predict, …)
  verifiers.yml      chain-id → list of block-explorer endpoints

<consumer-repo>/io/
  Fountain/
    Fountain.sh      prediction recipe — sources lib.sh, calls proto_predict
    <addr>.txt
    <addr>.yml
    <addr>.json
  Fountain1/
    Fountain1.sh     prediction recipe — sources lib.sh, calls clone_predict
    <addr>.txt
    <addr>.yml
```

Each `<contract>.sh` is the prediction recipe for that contract,
co-located with the artifacts it produces. Re-running the script
regenerates the artifacts from current inputs. Inputs come from the
repo's `.env` (mined salts/variants, factory addresses, args) and from
the contract source (bytecode via `forge inspect`).

There are **no per-repo orchestration scripts**. The two scripts in
crucible (`deploy.sh`, `verify.sh`) are the entire deployment surface
for every consumer repo.

## Deploy algorithm

Run `bash lib/crucible/script/deploy.sh <chain>` from a consumer repo's
root. The script defines a single recursive function:

```
deploy(addr):
    if addr has code on chain:
        return
    yml = lookup(addr)
    if yml.deployer is not Nick:
        deploy(yml.deployer)               # ensure prerequisite
    broadcast yml.contract/<addr>.txt to yml.deployer
```

Top-level: index every `io/*/<addr>.yml` into an `addr → yml` map, then
call `deploy(addr)` for every entry.

Each branch terminates either at an already-deployed address (memoized
via `cast code`) or at Nick's deployer (always present on every chain).
Memoization is implicit: once a contract is deployed in this run, the
next `deploy(addr)` call for the same address sees its code and returns
immediately. No cycle detection is needed — clones depend on prototypes
that were minted before them, so the dep graph is a DAG by
construction.

`cast code` is the source of truth for what exists on-chain, so
partial-failure recovery is automatic: rerun and the script picks up
where it left off. Re-deploying the full graph to a new chain is the
same command — `deploy.sh <newchain>`.

## Verification

The `<addr>.json` file is the Etherscan **standard-input JSON**: a
self-contained bundle of source files, compiler version, optimizer
settings, libraries, and constructor args, generated by
`forge verify-contract --show-standard-json-input`. Block explorers
accept this format directly — it tells them how to recompile the
contract and check the resulting bytecode against on-chain code.

Verification is deliberately separate from deployment because:

- It can lag deployment by minutes (the explorer's indexer needs to
  see the deploy tx before verification will succeed).
- It can fail or rate-limit independently of broadcast, and benefits
  from retry.
- A single chain often has multiple explorers (Etherscan + Sourcify,
  sometimes Blockscout) you want to push to.

`verify.sh <chain>` walks `io/<contract>/<addr>.json` and submits each
to every verifier configured for that chain, skipping addresses
already verified on a given explorer. Like `deploy.sh`, it is
idempotent: rerun until everything is green.

### Verifier configuration

`lib/crucible/script/verifiers.yml` maps chain ID to a list of
explorer endpoints:

```yaml
1:
  - kind: etherscan
    url: https://api.etherscan.io/v2/api
    keyEnv: ETHERSCAN_API_KEY
  - kind: sourcify
    url: https://sourcify.dev/server
8453:
  - kind: etherscan
    url: https://api.basescan.org/api
    keyEnv: BASESCAN_API_KEY
```

`verify.sh` iterates `(addr, verifier)` pairs, calling
`forge verify-contract` under the hood with the appropriate
`--verifier` and `--verifier-url` flags. API keys come from the env
vars named in `keyEnv`. Adding support for a new chain or explorer
means editing this file, not the script.

### Clones

Clones have no `<addr>.json` because an EIP-1167 proxy is not verified
by recompiling source — it is verified by linking it to its already-
verified implementation. `verify.sh` detects clones by absence of
`<addr>.json` and submits a proxy-verification request appropriate to
each explorer's API (e.g. Etherscan's `verifyproxycontract`
endpoint), which auto-detects the implementation and links the proxy
to the prototype's verified source.

## Salt mining

Salt mining is upstream of prediction: it produces the salt or variant
values that get committed to `.env` and consumed by the per-contract
prediction script. Mining is not part of normal deployment workflow —
once a salt is committed, it is reused across all chains.

Shared helpers in `lib.sh` may include `mine_proto` and `mine_clone`
wrappers that compute the right `initcode-hash` and `args-hash` inputs
and shell out to `saltminer`, but the artifacts under `io/<contract>/`
record only the resulting salt or variant, not the mining run.

## Migration: retiring `Proto.s.sol`

[`crucible/script/Proto.s.sol`](../script/Proto.s.sol) is the current
Solidity-based prototype-deployment helper. Under this design its
responsibilities split cleanly:

- **Prediction** moves to `io/<contract>/<contract>.sh`, which sources
  `lib/crucible/script/lib.sh` and calls `proto_predict`.
- **Broadcast** moves to `lib/crucible/script/deploy.sh`.
- **Verification** moves to `lib/crucible/script/verify.sh`.

`Proto.s.sol` will be deprecated and retired once downstream repos
(`solid`, `lepton`, `unispring`, and others) migrate their prototype
deployments to this layout. Until then it remains as-is so existing
deployment scripts continue to work.
