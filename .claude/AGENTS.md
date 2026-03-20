# AGENTS.md — Forge Command Safety

> Security guidance for AI agents working in uniteum Solidity repos.

## Denied Commands (settings.json)

The following commands are denied because they have **permanent, irreversible consequences**:

### `forge script *`
- Executes arbitrary Solidity that can deploy contracts and send transactions on live networks
- Can spend real ETH/tokens using the private key in `tx_key`
- The `--broadcast` flag sends transactions to mainnet — cannot be undone
- Scripts may call `vm.ffi()` to execute arbitrary shell commands if enabled in foundry.toml
- **Never run forge script without explicit user confirmation, even if not denied by settings**

### `forge create *`
- Deploys contracts directly to live networks using the user's private key
- Costs real gas and permanently associates the contract with the user's address
- Deployed contracts cannot be removed from the blockchain
- **Never deploy without explicit user confirmation**

### `forge verify-contract *`
- Publishes source code to Etherscan/block explorers permanently
- Could leak proprietary or unfinished contract code
- Uses the user's `ETHERSCAN_API_KEY`, tied to their identity
- **Never verify without explicit user confirmation**

## Allowed Commands (no prompting needed)

These are safe because they produce **no permanent side effects**:

- `forge build` / `forge build *` — compiles to local `out/`, overwritten on next build
- `forge test` / `forge test *` — runs in a local EVM fork, no state changes
- `forge fmt` / `forge fmt *` — reformats files locally, reversible via git
- `forge inspect *` — reads compiled artifact metadata, no writes
- `forge coverage *` — runs tests with coverage tracking, no writes beyond reports

## General Principle

**Allow without prompting** if all of these are true:
1. The action is local (no network calls, no external services)
2. The action is reversible (can be undone with git checkout or re-run)
3. The action does not spend funds or expose secrets

**Always confirm with the user** if any of these are true:
1. The action sends a transaction or deploys to a network
2. The action publishes code or data to an external service
3. The action uses a private key or API key
4. The action cannot be undone

Examples of safe actions (no prompt needed):
- Writing or editing local files
- Running builds, tests, formatting
- Reading blockchain state (e.g., `cast call`)

Examples requiring confirmation:
- `forge script --broadcast` (sends transactions)
- `forge create` (deploys contracts)
- `forge verify-contract` (publishes source)
- `git push` (publishes to remote)
- `git commit` (permanent history entry)
