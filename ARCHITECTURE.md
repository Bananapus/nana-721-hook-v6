# Architecture

## Purpose

`nana-721-hook-v6` is the shared tiered NFT layer for Juicebox V6. It lets projects sell NFT tiers, track reserves, route split payouts, and cash out NFTs without replacing core treasury accounting.

## System overview

`JB721TiersHook` is the runtime hook. `JB721TiersHookStore` is the accounting backend for tiers, supply, reserves, and lookup. The deployers package that hook into reusable flows for existing projects and new project launches.

Custom token URI resolvers usually live outside this repo, but they still affect the trusted surface seen by users.

## Core invariants

- the hook must not create alternate treasury accounting
- tier supply, burned counts, and reserves must stay coherent
- cash-out weight must reflect the intended tier economics
- reserve minting and split routing must not drift from stored tier state
- store-linked list and bitmap assumptions must stay valid under tier add, remove, and clean operations
- deployer wiring must preserve the expected ruleset and hook shape
- the per-tier owner-tracked voting-units trace must follow owned supply: it increments on mint, moves through transfers via owner checkpoints, and decrements on burn
- the active-vote-total traces must track only voting units delegated to nonzero delegates, both globally and per tier, increasing when an account delegates held units and decreasing when units move into undelegated custody

## Modules

| Module | Responsibility | Notes |
| --- | --- | --- |
| `JB721TiersHook` | Pay hook, cash-out hook, permissions, and project-facing execution | Runtime core |
| `JB721TiersHookStore` | Tier definitions, balances, reserve tracking, and accounting | Shared state |
| `JB721TiersHookDeployer` | Clone deployer for existing projects | Wiring helper |
| `JB721TiersHookProjectDeployer` | Project-launch deployer with hook setup | Launch helper |
| `JB721Hook` | Abstract 721 hook base | Shared behavior |
| `JB721Checkpoints` | IVotes-compatible checkpoint module (one clone per hook) | Tracks historical owner checkpoints, per-tier owner-tracked voting-unit totals, and global/per-tier active delegated vote totals |

The checkpoint module keeps four kinds of checkpointed state. Per-token owner checkpoints back `ownerOfAt` for snapshot-based reward eligibility. A per-tier owner-tracked voting-units trace (`_tierEligibleUnitsOf`, read via `getPastTierVotingUnits(tierId, blockNumber)`) is the tier-scoped analogue of a total-supply snapshot: it increments on mint, follows owner checkpoints through transfers, and decrements on burn.

The active delegated vote traces (`_activeSupplyCheckpoints` globally and `_tierActiveSupplyCheckpointsOf` per tier) are separate. They track voting units held by accounts with a nonzero delegate. If a holder self-delegates and later transfers a token into undelegated custody, those units leave the active totals; if the token returns to that already-delegated holder, those units become active again. Reward distributors that should exclude inactive custody read these active totals as denominators.

## Trust boundaries

- core accounting, pricing, and terminal authentication remain in `nana-core-v6`
- metadata resolvers can be project-specific and should be treated as trusted external surfaces
- the store is trusted by every hook that uses it
- deployers are trusted to wire the hook into the intended project and ruleset shape

## Critical flows

### Pay and mint

```text
payment arrives
  -> hook decodes metadata and tier choices
  -> store records mints, credits, supply changes, and reserve effects
  -> hook may route split payouts from forwarded funds
  -> collection state and balances update for the beneficiary
```

### Cash out

```text
cash out requested
  -> hook checks NFT-specific metadata and selected token IDs
  -> hook burns NFTs
  -> store records burn and supply effects
  -> terminal reclaims value using hook-aware cash-out math
```

## Accounting model

This repo owns tier accounting and NFT lifecycle logic. It does not own the canonical project ledger for balances, fees, or surplus.

The most important state lives in the store: remaining supply, burned counts, reserve tracking, and per-tier configuration.

## Security model

- store corruption has ecosystem-wide blast radius because many products reuse it
- reserve logic, discounts, and cash-out weight are the main economic risk surfaces
- split distribution and fallback behavior are part of correctness, not a secondary concern
- gas costs matter because some reads and writes scale with tier count

## Safe change guide

- review hook and store behavior together when changing tier lifecycle logic
- if reserve logic changes, re-check cash-out weight and pending reserve effects together
- if deployer behavior changes, re-check ruleset wiring and ownership transfer paths
- do not treat resolver behavior as proof that hook accounting is correct

## Canonical checks

- pay, mint, and redeem end-to-end behavior:
  `test/E2E/Pay_Mint_Redeem_E2E.t.sol`
- store and lifecycle invariants:
  `test/invariants/TierLifecycleInvariant.t.sol`
  `test/invariants/TieredHookStoreInvariant.t.sol`
- split-credit and deployer regressions:
  `test/regression/SplitCreditsMismatch.t.sol`
  `test/regression/ProjectDeployerRulesets.t.sol`

## Source map

- `src/JB721TiersHook.sol`
- `src/JB721TiersHookStore.sol`
- `src/JB721TiersHookDeployer.sol`
- `src/JB721TiersHookProjectDeployer.sol`
- `src/libraries/JB721TiersHookLib.sol`
