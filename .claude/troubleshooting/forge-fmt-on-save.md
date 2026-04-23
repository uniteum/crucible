# Format-on-Save Not Working for Solidity

## Symptom

Saving a `.sol` file in VSCode does not run `forge fmt`. The file
stays in whatever state you typed. Often "Format Document With..."
is missing from the Command Palette entirely. The repo looks
correctly configured: `.vscode/settings.json` sets
`editor.defaultFormatter: NomicFoundation.hardhat-solidity`,
`editor.formatOnSave: true`, and `solidity.formatter: forge`.

This problem recurs every few months when setting up a new repo.
**Do not start guessing config files.** Go straight to diagnosis.

## Diagnosis (always works)

The Nomic Hardhat Solidity extension shells out to:

```
forge fmt --raw -
```

When this command fails, **the extension fails silently** — no
notification, no error in the editor, no entry in "Format Document
With...". The error is only visible in one place:

1. **View → Output** in VSCode
2. In the Output panel's dropdown (top right), select **Solidity**
3. Save the `.sol` file
4. The real error appears in that panel

## Known causes and fixes

### Cause 0: Slang can't parse the pragma version (MOST COMMON)

The `NomicFoundation.hardhat-solidity` extension bundles **Slang**,
its own Solidity parser. Older versions of the bundled Slang only
support up to **0.8.28**. If the file has a pragma the bundled Slang
doesn't recognize, the Output panel shows:

```
[Info] No Slang-supported version (latest: 0.8.28) for Solidity
       found that satisfies the pragma directives: '^0.8.30'.
```

When this happens, the extension silently refuses to register a
formatter for the file. No error popup. "Format Document With..."
disappears. Save does nothing.

Seen in `uniswap-lookup` (2026-04-23).

**Fix:** update the `NomicFoundation.hardhat-solidity` extension to
its latest version — newer releases bundle a Slang that supports
0.8.30+. Reload window after updating.

If the extension is already on its latest version, install the newer
**`NomicFoundation.solidity`** extension (the Foundry-aware
successor) and change `[solidity].editor.defaultFormatter` in
`lib/crucible/.vscode/settings.json` from
`NomicFoundation.hardhat-solidity` to `NomicFoundation.solidity`.

**Do not lower the pragma.** All Uniteum Solidity is pinned to
0.8.30+ for EIP-1153 transient storage support
(see `crucible/.claude/rules/solidity.md`).

### Cause 1: `FOUNDRY_CONFIG` env var points to a non-existent path

Seen in `locale` (2026-03-17). The `.env` file had:

```
FOUNDRY_CONFIG=config/foundry.toml
```

When VSCode launched forge from the repo root, no `foundry.toml`
existed there, so `forge fmt` aborted with:

```
foundry.toml error: Config file 'config/foundry.toml' set in env var
'FOUNDRY_CONFIG' does not exist in TOML file provider
```

**Fix:** symlink the real config to the root and remove the env var:

```
ln -s config/foundry.toml foundry.toml
```

Then delete the `FOUNDRY_CONFIG=...` line from `.env`.

### Cause 2: forge can't find a `foundry.toml` from the cwd

If `forge fmt --raw -` is invoked from a directory with no
`foundry.toml` (or no symlink to one), it errors out. Every Solidity
repo in this workspace must have a `foundry.toml` (or a symlink to
`lib/crucible/foundry.toml`) at its root.

### Cause 3: missing `.prettierignore`

If a Prettier-based extension is also installed, it can claim the
formatter slot and run prettier-plugin-solidity instead of forge.
Add `.prettierignore` at the repo root:

```
# Ignore Solidity files - use forge fmt instead
*.sol

# Foundry output
out/
cache/
```

Reload the VSCode window after adding it.

## What NOT to do

- Do not assume the problem is `.prettierignore` until you have
  checked the **Solidity Output panel**. Most of the time the real
  error is something else and the panel reveals it instantly.
- Do not waste time inspecting `.vscode/settings.json` byte-for-byte
  against a working repo. The shared settings file is symlinked from
  `lib/crucible/.vscode/settings.json` and is identical everywhere
  by construction.
- Do not guess at extension IDs or workspace-vs-folder scope. The
  Output panel is faster than any of that.
