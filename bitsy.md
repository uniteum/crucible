---
title: Bitsy
description: >-
  A contract is Bitsy if it is immutable, permissionless, governance-free,
  cloned, deterministic, direct, composable, and math-only.
  An open standard for minimal, permanent on-chain primitives.

# Navigation
nav_order: 3
has_children: false

# Metadata
last_updated: 2026-03-30
status: draft
---

# Bitsy

A contract is **Bitsy** if it satisfies eight properties — the
concrete, testable form of the [design philosophy](/philosophy/)
behind the Uniteum protocols. All eight. No exceptions, no
"partially Bitsy," no spectrum.

The term is not trademarked. Anyone can build Bitsy contracts.
If a contract meets the criteria below, it qualifies — regardless of
who deployed it or what ecosystem it belongs to.

---

## The eight properties

### 1. Immutable

No upgrade mechanism. No admin key. No proxy that can be repointed.
No `selfdestruct`. The bytecode at deployment is the bytecode forever.

**Test:** Is there any address, key, or governance process that can
alter the contract's logic after deployment? If yes, it is not
Bitsy.

### 2. Permissionless

Every external function is callable by every address. No whitelist,
no role check, no `onlyOwner`. The contract does not know or care
who is calling it.

**Test:** Does any function check `msg.sender` against a privileged
list? If yes, it is not Bitsy.

### 3. Zero governance

No governance token. No voting mechanism. No parameter that can be
changed after deployment. Fee rates, reserve ratios, and behavioral
rules are constants baked into the bytecode.

**Test:** Is there any on-chain or off-chain process that can change
the contract's parameters? If yes, it is not Bitsy.

### 4. Cloned

Every instance of the contract is a minimal proxy clone of a single
implementation. Same logic for every instance — no per-instance
configuration that alters behavior, no constructor arguments that
change the rules.

**Test:** Do two instances of the same protocol run different code
or operate under different rules? If yes, it is not Bitsy.

### 5. Deterministic

Deployed via CREATE2. The contract address is derived from its
parameters. Same parameters produce the same address on every
EVM-compatible chain.

**Test:** Can you compute the contract's address before deployment
from its inputs alone? If not, it is not Bitsy.

### 6. Direct

Every operation is a single function call. No multi-step workflows
beyond standard ERC-20 approvals. Usable from a block explorer
without a frontend, SDK, or off-chain signature.

**Test:** Does using the contract require a frontend, a relayer,
or an off-chain step? If yes, it is not Bitsy.

### 7. Composable

The contract operates through well-defined interfaces. Where it
produces tokens, those tokens are standard ERC-20s. Where it
exposes other functionality, it does so through public functions
with clear inputs and outputs — no off-chain coordination, no
proprietary coupling, no requirement that callers use a specific
SDK or wrapper.

**Test:** Can other contracts interact with this contract using
only its public interface, without proprietary adapters or
off-chain steps? If not, it is not Bitsy.

### 8. Pure math

Prices and state transitions are determined entirely by on-chain
invariants. No oracles, no external data feeds, no off-chain
computation. Arbitrage maintains correctness.

**Test:** Does the contract depend on any data source outside its
own state and its invariant math? If yes, it is not Bitsy.

---

## Bitsy contracts in practice

Every Uniteum protocol is Bitsy:

| Protocol                       | Implementation              | Instances are clones of         |
|--------------------------------|-----------------------------|---------------------------------|
| [Solid](/solid/)               | Constant-product AMM with virtual reserve | [NOTHING](/solid/nothing/) |
| [Liquid](/liquid/)             | Hub-and-spoke AMM with 2x mint           | Hub                        |
| [Uniteum](/uniteum/)           | Geometric mean triads                    | The Uniteum contract       |
| [Lepton](/lepton/)             | Fixed-supply token factory               | Lepton prototype           |

These are not the only contracts that could qualify. Any contract
that passes all eight tests is Bitsy, whether or not it has
any connection to Uniteum.

---

## Why this matters

Bitsy contracts have a specific trust model: **trust the math,
not the operator.** There is no operator.

This eliminates entire categories of risk:

- **Rug pulls** — there is no admin key to drain funds.
- **Governance attacks** — there is no governance to capture.
- **Upgrade risk** — there is no upgrade path to exploit.
- **Oracle manipulation** — there are no oracles to manipulate.
- **Censorship** — there is no whitelist to exclude you from.

What remains is **code risk**: the possibility that the math itself
is wrong. That risk cannot be eliminated. It can only be managed
by keeping the code simple enough to read, and by deploying
immutably so the code you audit is the code that runs.

---

## Relationship to the design philosophy

The eight Bitsy properties are the formalized, testable version
of the [design philosophy](/philosophy/) that guided the Uniteum
protocols. The philosophy page explains *why* these choices were
made. This page defines *what* the choices are, concretely enough
that anyone can check whether a given contract qualifies.

---

## Using the term

If you deploy a contract that satisfies all eight properties, you
can call it Bitsy. No permission needed. No registry. No
certification process.

The value of the term depends on it meaning something specific.
A contract that is "mostly Bitsy" or "Bitsy except for
governance" is not Bitsy. The properties are binary and the
list is closed.
