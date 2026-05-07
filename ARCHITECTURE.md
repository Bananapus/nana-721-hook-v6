# Architecture

## Purpose

`nana-721-hook-v6` is the shared tiered NFT layer for Juicebox V6. It lets projects sell NFT tiers, track reserves, route split payouts, and cash out NFTs without replacing core treasury accounting.

## System Overview

`JB721TiersHook` is the runtime hook. `JB721TiersHookStore` is the accounting backend for tiers, supply, reserves, and lookup. The deployers package that hook into reusable flows for existing projects and new project launches.

Custom token URI resolvers usually live outside this repo, but they still affect the trusted surface seen by users.

## Core Invariants

- the hook must not create alternate treasury accounting
- tier supply, burned counts, and reserves must stay coherent
- cash-out weight must reflect the intended tier economics
- reserve minting and split routing must not drift from stored tier state
- store-linked list and bitmap assumptions must stay valid under tier add, remove, and clean operations
- deployer wiring must preserve the expected ruleset and hook shape

## Modules

| Module | Responsibility | Notes |
| --- | --- | --- |
| `JB721TiersHook` | Pay hook, cash-out hook, permissions, and project-facing execution | Runtime core |
| `JB721TiersHookStore` | Tier definitions, balances, reserve tracking, and accounting | Shared state |
| `JB721TiersHookDeployer` | Clone deployer for existing projects | Wiring helper |
| `JB721TiersHookProjectDeployer` | Project-launch deployer with hook setup | Launch helper |
| `JB721Hook` | Abstract 721 hook base | Shared behavior |

## Trust Boundaries

- core accounting, pricing, and terminal authentication remain in `nana-core-v6`
- metadata resolvers can be project-specific and should be treated as trusted external surfaces
- the store is trusted by every hook that uses it
- deployers are trusted to wire the hook into the intended project and ruleset shape

## Critical Flows

### Pay And Mint

```text
payment arrives
  -> hook decodes metadata and tier choices
  -> store records mints, credits, supply changes, and reserve effects
  -> hook may route split payouts from forwarded funds
  -> collection state and balances update for the beneficiary
```

### Cash Out

```text
cash out requested
  -> hook checks NFT-specific metadata and selected token IDs
  -> hook burns NFTs
  -> store records burn and supply effects
  -> terminal reclaims value using hook-aware cash-out math
```

## Accounting Model

This repo owns tier accounting and NFT lifecycle logic. It does not own the canonical project ledger for balances, fees, or surplus.

The most important state lives in the store: remaining supply, burned counts, reserve tracking, and per-tier configuration.

## Security Model

- store corruption has ecosystem-wide blast radius because many products reuse it
- reserve logic, discounts, and cash-out weight are the main economic risk surfaces
- split distribution and fallback behavior are part of correctness, not a secondary concern
- gas costs matter because some reads and writes scale with tier count

## Safe Change Guide

- review hook and store behavior together when changing tier lifecycle logic
- if reserve logic changes, re-check cash-out weight and pending reserve effects together
- if deployer behavior changes, re-check ruleset wiring and ownership transfer paths
- do not treat resolver behavior as proof that hook accounting is correct

## Canonical Checks

- pay, mint, and redeem end-to-end behavior:
  `test/E2E/Pay_Mint_Redeem_E2E.t.sol`
- store and lifecycle invariants:
  `test/invariants/TierLifecycleInvariant.t.sol`
  `test/invariants/TieredHookStoreInvariant.t.sol`
- split-credit and deployer regressions:
  `test/regression/RegressionSplitCreditsMismatch.t.sol`
  `test/regression/ProjectDeployerRulesets.t.sol`

## Source Map

- `src/JB721TiersHook.sol`
- `src/JB721TiersHookStore.sol`
- `src/JB721TiersHookDeployer.sol`
- `src/JB721TiersHookProjectDeployer.sol`
- `src/libraries/JB721TiersHookLib.sol`
