# Deployment Migration

> **Status: forward-looking.** Tracks the rollout of
> [deployment.md](deployment.md) across consumer repos. All work lands
> on the `predict` branch in each repo and merges only after every
> repo's `deploy.sh <chain>` round-trips successfully on a test chain
> (Sepolia or equivalent).

## Scope

Five repos in dependency order:

1. **crucible** — provides the new shared scripts.
2. **lepton** — deploys the Lepton/ICoinage prototype that all
   subsequent token mints route through.
3. **uniteum** — deploys the algebraic-protocol primitives, including
   the Uniteum 1 hub token.
4. **locale** — deploys per-chain reference contracts
   (`NativeSymbolLookup`, etc.).
5. **unispring** — consumer of all of the above; deploys the Manifold
   and Mimicry families plus their clones.

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

- [ ] Migrate `Lepton.sh`, `FFF.sh`, `OOO.sh`, `pi.sh` to
      `io/<contract>/<contract>.sh` calling `proto_predict`.
- [ ] Add `<addr>.yml` alongside existing `<addr>.txt` and
      `<addr>.json` artifacts (yml is the new file).
- [ ] Smoke-test `bash lib/crucible/script/deploy.sh sepolia`
      reproduces the existing mainnet addresses.

## locale

Confirmed: locale deploys four StringLookup-family prototypes via
Nick. `NativeSymbolLookup` (`0x6a50503D...`) is a **clone** of locale's
`StringLookup` prototype (per
[unispring/script/MimicryDeploy.s.sol](../../unispring/script/MimicryDeploy.s.sol)
which describes it as "chain-local IStringLookup"), not a separate
contract — so locale covers it.

- [ ] Migrate `AddressLookup.sh`, `ImmutableUintToAddress.sh`,
      `ImmutableUintToUint.sh`, `StringLookup.sh` to
      `io/<contract>/<contract>.sh` calling `proto_predict`.
- [ ] Decide where the `NativeSymbolLookup` clone lives — locale (as
      a sample/seed clone) or unispring (as one of its required
      runtime deps). Probably locale.

## uniteum

**Divergent layout — needs reconciling with the design.** uniteum
currently uses `forge script` Solidity scripts (`Unit.s.sol`,
`Multiply.s.sol`, `UnitHelper.s.sol`) and a per-chain `io/` layout
(`io/1/`, `io/11155111/`) because `Unit`'s constructor takes a
chain-specific `HUB_SOLID` address. This breaks the
"chain-independent artifacts" invariant for `Unit` specifically.

- [ ] Migrate the chain-independent prototypes (`Multiply`,
      `UnitHelper`, anything else with no chain-varying constructor
      args) to the new layout straightforwardly.
- [ ] Decide what to do about `Unit`. Options:
      (a) keep per-chain `io/<chain>/Unit/<addr>.{txt,yml,json}` as
          a documented exception in the design doc;
      (b) factor `HUB_SOLID` out of the constructor (immutable
          stored in a chain-local lookup, set later);
      (c) deploy `Unit` only on chains where the hub already exists,
          and predict per-chain.
- [ ] Replace `verifyUnit.sh` usage with the shared `verify.sh`
      once `verifiers.yml` covers Etherscan.

## unispring

- [ ] Migrate prototypes: Manifold, Mimicry, Fountain,
      NeutrinoChannelProto, NeutrinoSourceProto, ManifoldProto.
- [ ] Migrate clones: `Fountain1`, the hub spoke, channel and source
      clones, mimic tokens.
- [ ] Move `mine-*-salt.sh` logic into `lib.sh` helpers; keep mined
      values in `.env`.
- [ ] Move `check-hub-salt.sh` logic into a `lib.sh` helper invoked
      by the relevant `<contract>.sh`.
- [ ] Delete legacy [`script/*.sh`](../../unispring/script/) once
      every artifact is committed.
- [ ] Smoke-test full graph deploy on a fresh test chain.

## Open questions

- **Chain-dependent constructor args.** `uniteum/Unit` takes a
  chain-specific `HUB_SOLID`, breaking chain-independent artifacts.
  Other consumers may have similar shapes — survey before finalizing
  the doc's invariant.
- **Forge-script vs bash for prototypes.** uniteum uses Solidity
  `*.s.sol` scripts; lepton/locale/unispring use bash with `cast`.
  Pick one canonical style or document that both are acceptable
  (the difference is invisible once `<addr>.{txt,yml,json}` exist).
- **Verifiers.yml location.** Ship with crucible (chains rarely
  change) or live per-repo? Default crucible; per-repo override may
  be useful.
- **Sourcify clones.** Does Sourcify auto-detect EIP-1167 the way
  Etherscan does, or do we need to upload the proxy bytecode
  separately? Affects `verify.sh` clone branch.
- **`kind: presigned` for Nick** on chains without him — defer or
  scope in?
