# Deployment Migration

> **Status: forward-looking.** Tracks the rollout of
> [deployment.md](deployment.md) across consumer repos. All work lands
> on the `predict` branch in each repo and merges only after every
> repo's `deploy.sh <chain>` round-trips successfully on a test chain
> (Sepolia or equivalent).

## Scope

Focus: **Mimicry** and its dependency closure.

```
locale/AddressLookup (prototype)
   └─ PoolManagerLookup (clone)        ─┐
locale/StringLookup (prototype)         │
   └─ NativeSymbolLookup (clone)        │
lepton/Lepton (== ICoinage)             │
unispring/Fountain (prototype)  ────────┘  takes PoolManagerLookup
unispring/Mimicry (prototype)              takes Fountain, ICoinage,
                                                 NativeSymbolLookup
```

In-scope work by repo:

1. **crucible** — provides the new shared scripts.
2. **lepton** — `Lepton` prototype (== `ICoinage` at `0x1EB890...`).
3. **locale** — `AddressLookup` and `StringLookup` prototypes.
4. **unispring** — the two locale clones (`PoolManagerLookup`,
   `NativeSymbolLookup`) plus `Fountain` and `Mimicry` prototypes.

`AddressLookup`'s `make(keyValues, variant)` keys clones by a
chain-independent `(chainId, address)` mapping XOR'd with a variant,
so clone addresses are the same on every chain even though their
`value()` is chain-local. The Mimicry path therefore stays fully
chain-independent.

**Cheap follow-on:** `Manifold` is a sibling of Mimicry that takes
only `Fountain` in its constructor, so once Fountain is migrated the
Manifold prototype is essentially free. The hub-and-spoke deployments
that Manifold *enables* (NeutrinoChannelProto, NeutrinoSourceProto,
hub token, spoke clones) are deferred — they pull in uniteum.

**Deferred:**

- **uniteum** entirely — the per-chain `HUB_SOLID` constructor arg
  for `Unit` breaks the chain-independence invariant and needs a
  separate design pass.
- **lepton extras**: `FFF`, `OOO`, `pi` — other coinage variants not
  on the Mimicry path.
- **locale extras**: `ImmutableUintToAddress`, `ImmutableUintToUint`
  — not consumed by Mimicry.
- **unispring extras**: `NeutrinoChannelProto`, `NeutrinoSourceProto`,
  hub/spoke deployment, mimic clones (the per-token `1xUSDC` etc. are
  runtime usage, separate from prototype migration).

Submodule libraries that ship only Solidity source (`clones`,
`context`, `erc20`, `icoinage`, `ierc20`, `ilookup`, `iuniswap`,
`ownable`) are out of scope — they deploy nothing of their own.

## Branch

Every repo uses the same branch name: **`predict`**. PRs may be
opened independently but should not merge until the dep chain below
them has merged, so addresses predicted on `predict` branches stay
stable through to mainnet rollout.

## crucible (this repo)

- [ ] `script/lib.sh` — `proto_predict`, `clone_predict`, `mine_proto`,
      `mine_clone`, `write_yml`, `write_txt`, `write_verify_json`.
- [ ] `script/deploy.sh` — recursive deploy, existence-checked via
      `cast code`.
- [ ] `script/verify.sh` — multi-explorer, idempotent, skips
      already-verified addresses.
- [ ] `script/verifiers.yml` — chain-id → list of explorer endpoints.
- [ ] Mark [`script/Proto.s.sol`](../script/Proto.s.sol) deprecated
      with a banner comment pointing here.
- [ ] Update [`README.md`](../README.md) `## ProtoScript` section to
      reference the new pipeline.

## lepton

Confirmed: Lepton is the prototype at
`0x1EB8901612767C04b3819E8A743ADCe88F9Fe110` (referred to as
`ICoinage` in unispring's env). Deployed via Nick at salt
`0x000000000000000000000000000000000000000000000000000000002b3fbfee`.

- [ ] Migrate `Lepton.sh` to `io/Lepton/Lepton.sh` calling
      `proto_predict`.
- [ ] Add `<addr>.yml` alongside existing `<addr>.txt` and
      `<addr>.json` artifacts (yml is the new file).
- [ ] Smoke-test `bash lib/crucible/script/deploy.sh sepolia`
      reproduces the existing mainnet address.

`FFF`, `OOO`, `pi` are deferred — same pattern as Lepton, can follow
later without changing scope.

## locale

Confirmed: locale deploys four StringLookup-family prototypes via
Nick. `NativeSymbolLookup` (`0x6a50503D...`) is a **clone** of locale's
`StringLookup` prototype (per
[unispring/script/MimicryDeploy.s.sol](../../unispring/script/MimicryDeploy.s.sol)
which describes it as "chain-local IStringLookup"), not a separate
contract — so locale covers it.

- [ ] Migrate `AddressLookup.sh` to `io/AddressLookup/AddressLookup.sh`
      — required: Fountain reads the V4 PoolManager via a clone of it.
- [ ] Migrate `StringLookup.sh` to `io/StringLookup/StringLookup.sh`
      — required: Mimicry reads the chain's native gas-token symbol
      via a clone of it.

The clones themselves (`PoolManagerLookup`, `NativeSymbolLookup`) are
consumer-owned and live in unispring/io/, since unispring picks the
keyValues mapping and consumes the resulting addresses. Locale only
ships the prototypes here.

`ImmutableUintToAddress` and `ImmutableUintToUint` are deferred.

## unispring

In-scope: two locale clones, then `Fountain`, then `Mimicry`.

- [ ] Add `io/PoolManagerLookup/PoolManagerLookup.sh` — clone of
      locale's `AddressLookup` keyed by the V4 PoolManager mapping
      `(chainId → V4 PoolManager addr)`. `clone_predict` writes
      `<addr>.txt` (factory call to `AddressLookup.make`) and
      `<addr>.yml`. No `.json`.
- [ ] Add `io/NativeSymbolLookup/NativeSymbolLookup.sh` — clone of
      locale's `StringLookup` keyed by the native-symbol mapping.
- [ ] Migrate `Fountain.sh` to `io/Fountain/Fountain.sh` calling
      `proto_predict` (Nick + mined salt `0x...01c8688910`,
      constructor takes `PoolManagerLookup`).
- [ ] Migrate `Mimicry.sh` to `io/Mimicry/Mimicry.sh` calling
      `proto_predict` (Nick + mined salt `0x...bdc7f617`,
      constructor takes `Fountain`, `ICoinage`, `NativeSymbolLookup`).
- [ ] Smoke-test `bash lib/crucible/script/deploy.sh sepolia`
      reproduces the existing mainnet addresses end-to-end:
      AddressLookup → PoolManagerLookup clone, StringLookup →
      NativeSymbolLookup clone, Lepton, Fountain, Mimicry.

Cheap follow-on (do if it falls out for free):

- [ ] Migrate `Manifold.sh` to `io/Manifold/Manifold.sh` (Nick + salt
      0x0, constructor takes only `Fountain`).

Deferred within unispring:

- `mine-hub-salt.sh`, `check-hub-salt.sh`, `mine-icoinage-salt.sh`
  — keep as-is until we tackle the hub/spoke deployments.
- `Fountain1`, hub clones, NeutrinoChannelProto, NeutrinoSourceProto,
  per-mimic-token clones.

## Open questions

- **Verifiers.yml location.** Ship with crucible (chains rarely
  change) or live per-repo? Default crucible; per-repo override may
  be useful.
- **Sourcify clones.** Does Sourcify auto-detect EIP-1167 the way
  Etherscan does, or do we need to upload the proxy bytecode
  separately? Affects `verify.sh` clone branch.
- **`kind: presigned` for Nick** on chains without him — defer or
  scope in?

## Out-of-scope, parked for later

Tracked here so they don't get lost when we revisit:

- **uniteum's chain-dependent constructor args.** `Unit` takes a
  chain-specific `HUB_SOLID`. Resolving this is a design problem,
  not just a refactor — defer until the Mimicry path is shipped.
  Possible directions: per-chain `io/<chain>/Unit/...` exception,
  factor `HUB_SOLID` out of the constructor, or predict per-chain.
- **Forge-script vs bash style.** uniteum uses Solidity `*.s.sol`;
  lepton/locale/unispring use bash with `cast`. Pick one canonical
  style or document both as acceptable.
