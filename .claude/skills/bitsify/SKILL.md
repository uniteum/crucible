---
name: bitsify
description: >-
  Convert a Solidity contract into a Bitsy contract — immutable,
  permissionless, governance-free, cloned, deterministic, direct,
  composable, and math-only. Use when the user wants to make a
  contract Bitsy or asks to apply the Bitsy pattern.
disable-model-invocation: true
argument-hint: <path-to-contract>
allowed-tools: Read, Grep, Glob, Edit, Write, Bash
---

# Bitsify — Convert a Solidity contract to the Bitsy pattern

You are converting a Solidity contract into a **Bitsy** contract.
A Bitsy contract satisfies eight properties: immutable, permissionless,
governance-free, cloned, deterministic, direct, composable, and
math-only.

The input is a path to a Solidity contract file: `$ARGUMENTS`

## Step 0: Read and understand

Read the target contract. Before making any changes, identify:

- **Constructor parameters** — these become `make()` / `zzInit()` args
  and salt inputs.
- **Access control** — `onlyOwner`, `Ownable`, role checks, `msg.sender`
  guards. These will be removed.
- **Mutable parameters** — setters, governance hooks, adjustable fees,
  pause mechanisms. These will be removed or baked in as constants.
- **Oracle dependencies** — external price feeds, Chainlink, TWAP.
  Flag these for the user — replacing oracles with invariant math
  requires a redesign and cannot be automated.
- **Upgrade mechanisms** — proxies, `delegatecall`, `selfdestruct`,
  UUPS, transparent proxy. These will be removed.

Present your analysis to the user before proceeding. Group findings
into:

1. **Mechanical changes** (you will handle these)
2. **Judgment calls** (mutable params that could be constants — ask
   the user what values to bake in)
3. **Design changes** (oracle replacement, architecture shifts — flag
   for the user, do not attempt without discussion)

## Layout rule

Place the factory methods (`made`, `make`, `zzInit`) **at the end**
of the contract, after the original business logic. The PROTO
immutable goes at the top with other state declarations. This keeps
the contract's core logic front and center, with the cloning
machinery grouped together at the bottom — matching the Etherscan
read experience where users see business functions first.

```
contract Foo {
    // — immutables (including PROTO) —
    // — state variables —
    // — errors, events, modifiers —
    // — constructor —
    // — core business logic (unchanged) —
    // — factory: made(), make(), zzInit() —
}
```

## Step 1: Add the Clones import and self-referential immutable

Add the Clones library import. Use the version from the Uniteum
repos if available in the project's dependencies, otherwise use
OpenZeppelin's `@openzeppelin/contracts/proxy/Clones.sol`.

Add the self-referential immutable. Name it after the contract's
role. Convention from existing Bitsy contracts:

```solidity
// The prototype instance. On clones, this points back to the
// original deployment.
ContractName public immutable PROTO = address(this);
// or, if the contract has a domain-specific name:
// ISolid public immutable NOTHING = this;
// Liquid public immutable HUB = this;
// IMob public immutable MOB = this;
```

Use the typed self-reference (`ContractName`, not `address`) when
the contract calls its own functions on the prototype.

## Step 2: Convert the constructor to `zzInit()`

### 2a: Empty the constructor

Move initialization logic out of the constructor. The constructor
should only:
- Call parent constructors with fixed values
- Set immutables (these are baked into bytecode and shared by clones)

```solidity
constructor() ERC20("", "") {}
```

### 2b: Create `zzInit()`

Create a public initialization function with a prototype guard.
The naming convention is `zzInit` (two z's) — this sorts last on
Etherscan's function list, keeping it out of users' way.

```solidity
/// @notice Initializer called by the prototype on a freshly
///         deployed clone. Reverts if called by anyone else.
function zzInit(/* former constructor params */) public {
    if (msg.sender != PROTO) revert Unauthorized();
    // ... initialization logic from the old constructor ...
}
```

**Guard pattern options** (pick one):

- **`msg.sender` check** (preferred): `if (msg.sender != PROTO) revert Unauthorized();`
- **State check** (when the prototype can't call directly):
  `if (bytes(_symbol).length != 0) revert AlreadyInitialized();`

If the contract doesn't already define an `Unauthorized` error,
add one:

```solidity
error Unauthorized();
```

### 2c: Handle ERC-20 metadata

If the contract is an ERC-20, name and symbol must be stored in
regular storage (not immutables) so clones can have distinct
metadata. Override `name()` and `symbol()` to read from storage:

```solidity
string internal _name;
string internal _symbol;

function name() public view override returns (string memory) {
    return _name;
}

function symbol() public view override returns (string memory) {
    return _symbol;
}
```

Set `_name` and `_symbol` in `zzInit()`, not in the constructor.

## Step 3: Add `made()` — deterministic address prediction

Add a view function that computes the deterministic address for a
given set of parameters without deploying:

```solidity
function made(/* parameters */)
    public
    view
    returns (bool exists, address home, bytes32 salt)
{
    // Validate inputs
    // ...

    // Derive salt from ALL parameters that define the instance
    salt = keccak256(abi.encode(param1, param2, ...));

    // Predict the CREATE2 address
    home = Clones.predictDeterministicAddress(
        address(PROTO), salt, address(PROTO)
    );

    // Check if already deployed
    exists = home.code.length > 0;
}
```

**Salt design rules:**
- Include every parameter that makes this instance distinct.
- Use `abi.encode` (not `abi.encodePacked`) to avoid collisions.
- If the creator's identity should differentiate instances (like
  Lepton), include `msg.sender` / maker address in the salt.
- If instances should be globally unique by content (like Solid's
  name+symbol), omit the creator.

## Step 4: Add `make()` — idempotent factory

Add the factory function. It must be idempotent: calling it twice
with the same parameters returns the same address.

```solidity
function make(/* parameters */)
    external
    returns (IContractName instance)
{
    if (this != PROTO) {
        // Forward to prototype if called on a clone
        instance = PROTO.make(/* parameters */);
    } else {
        (bool exists, address home, bytes32 salt) =
            made(/* parameters */);
        instance = IContractName(home);
        if (!exists) {
            home = Clones.cloneDeterministic(
                address(PROTO), salt, 0
            );
            ContractName(home).zzInit(/* parameters */);
        }
    }
}
```

**Clone forwarding**: The `if (this != PROTO)` block lets users
call `make()` on any clone and have it forwarded to the prototype.
This is convenient but optional.

## Step 5: Strip access control

Remove:
- `Ownable`, `AccessControl`, and similar inheritance
- `onlyOwner`, `onlyRole`, `onlyAdmin` modifiers
- `owner()`, `renounceOwnership()`, `transferOwnership()`
- Any `require(msg.sender == ...)` that gates a business function

**Exception**: Identity checks that verify the caller is a valid
clone of the same prototype are acceptable. These are not privilege
checks — they prevent arbitrary external contracts from calling
internal coordination functions. Pattern:

```solidity
modifier onlyClone() {
    if (msg.sender != address(PROTO)) {
        // Verify caller is a valid clone
        (, address expected,) = made(/* caller's params */);
        if (msg.sender != expected) revert Unauthorized();
    }
    _;
}
```

## Step 6: Strip mutability

Remove:
- Setter functions (`setFee()`, `setOracle()`, `updateConfig()`)
- Pause/unpause mechanisms (`whenNotPaused`, `Pausable`)
- Emergency functions (`emergencyWithdraw`, `shutdown`)
- Governance hooks (`propose`, `vote`, `execute` — unless governance
  IS the contract's purpose)
- Fee switches, parameter tuning, upgradeable references

For each removed parameter, either:
- **Bake it in as a constant** (ask the user for the value), or
- **Remove the feature entirely** if it doesn't make sense as a
  fixed value.

## Step 7: Strip upgrade mechanisms

Remove:
- UUPS, transparent proxy, beacon proxy patterns
- `selfdestruct` / `SELFDESTRUCT` opcode usage
- `delegatecall` to mutable targets
- Storage gaps (`__gap`)
- Initializable guards from OpenZeppelin's upgradeable contracts
  (replace with the simpler `zzInit` pattern)

## Step 8: Flag oracle dependencies

If the contract uses external data feeds (Chainlink, Uniswap TWAP,
custom oracles), **do not silently remove them**. Instead:

1. List every oracle dependency found.
2. Explain what each oracle provides.
3. Ask the user how they want to replace each one — options include:
   - Constant-product AMM invariant (`x * y = k`)
   - Geometric mean invariant (`w = sqrt(u * v)`)
   - Fixed rate baked into the contract
   - Removal of the feature that required the oracle
4. Do not proceed with oracle replacement without explicit guidance.

## Step 9: Verify

After all changes, check the result against each Bitsy property:

1. **Immutable**: No upgrade mechanism, no admin key, no proxy
   repointing, no `selfdestruct`.
2. **Permissionless**: No `msg.sender` privilege checks on business
   functions. Identity checks (is caller a valid clone?) are OK.
3. **Zero governance**: No voting, no adjustable parameters post-deploy.
4. **Cloned**: Uses EIP-1167 minimal proxy via `Clones` library.
5. **Deterministic**: `make()` uses CREATE2 with content-derived salt.
   `made()` predicts the address.
6. **Direct**: Every operation is a single function call. No multi-step
   workflows beyond standard ERC-20 approvals.
7. **Composable**: Tokens are standard ERC-20. Interfaces are public
   and well-defined.
8. **Pure math**: No oracles, no external data feeds. Pricing (if any)
   is determined by on-chain invariants.

Report any property that cannot be satisfied and explain why.

## Output

Present the transformed contract to the user. Summarize:
- What was changed mechanically
- What was baked in (and at what values)
- What was removed
- What still needs design work (oracles, architecture)
