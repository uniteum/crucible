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

- [ ] Confirm Lepton is the prototype currently deployed at
      `0x1EB8901612767C04b3819E8A743ADCe88F9Fe110` (referred to as
      `ICoinage` in unispring's env).
- [ ] Replace [`script/*.sh`](../../lepton/script/) with
      `io/Lepton/Lepton.sh` calling `proto_predict`.
- [ ] Generate `<addr>.txt`, `<addr>.yml`, `<addr>.json`.
- [ ] Smoke-test `bash lib/crucible/script/deploy.sh sepolia`
      reproduces the existing mainnet address.

## uniteum

- [ ] Audit [`uniteum/script/`](../../uniteum/script/) for which
      contracts are deployed (Multiply, Unit, UnitHelper, hub token).
- [ ] Migrate each prototype to `io/<contract>/<contract>.sh`.
- [ ] Migrate hub token (`Uniteum 1` at
      `0x7D5B1349157335aEEB929080a51003B529758830`) — likely a clone
      minted by Lepton.
- [ ] Replace `verifyUnit.sh` usage with the shared `verify.sh`.

## locale

- [ ] Audit [`locale/script/`](../../locale/script/) — confirm
      `NativeSymbolLookup` (`0x6a50503D35804A057fB1754172ABc96242a1C300`)
      and any other per-chain refs are deployed here.
- [ ] Migrate each to `io/<contract>/<contract>.sh`.

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

- Is `lepton` actually the deployer of `ICoinage`, or is there a
  separate `coinage` repo? Confirm before opening the lepton PR.
- Should `verifiers.yml` ship with crucible or live per-repo? Default
  assumption is crucible (chains rarely change), but per-repo
  override may be useful.
- For Sourcify clones: does Sourcify auto-detect EIP-1167 the way
  Etherscan does, or do we need to upload the proxy bytecode
  separately? Affects `verify.sh` clone branch.
- `kind: presigned` for Nick on chains without him — defer or scope
  in?
