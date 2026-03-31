# Audit Instructions

This repo is the tiered ERC-721 hook system for Juicebox payments and NFT cash-outs. Audit it as a shared primitive used by many other repos.

## Objective

Find issues that:
- let users mint tiers more cheaply than intended
- over-mint, under-burn, or miscount reserves, credits, or supply
- route split funds incorrectly or let split paths distort token issuance
- let NFT cash-outs reclaim more value than intended
- corrupt shared store state across different hook instances

## Scope

In scope:
- `src/JB721TiersHook.sol`
- `src/JB721TiersHookStore.sol`
- `src/JB721TiersHookDeployer.sol`
- `src/JB721TiersHookProjectDeployer.sol`
- `src/abstract/`
- `src/interfaces/`
- `src/libraries/`
- `src/structs/`
- deployment scripts in `script/`

This repo is depended on by Defifa, Croptop, Banny, Revnets, and omnichain deployers. Bugs here often have ecosystem-wide blast radius.

## System Model

The hook can act as:
- a data hook for payment and cash-out accounting inputs
- a pay hook that mints NFTs
- a cash-out hook that burns NFTs and computes reclaim weight

Key moving parts:
- `JB721TiersHookStore` holds compact tier state
- hook instances read and mutate tier data through the store
- tier prices, discounts, reserves, credits, split percentages, and category order shape mint behavior
- optional token URI resolvers can override metadata generation

The most important design subtlety is that this repo affects both:
- NFT state
- core Juicebox accounting inputs and fulfillment order

That combination is why small-looking mistakes here often become ecosystem-wide economic bugs.

## Critical Invariants

1. Supply caps hold
No tier may mint beyond its configured total supply once purchases, owner mints, and pending reserves are all considered.

2. Reserve accounting is exact
Pending reserves must neither disappear nor inflate reclaim denominators beyond what the design intends.

3. Split routing matches accounting
If part of a mint price is routed to splits, token issuance and treasury accounting must reflect only the intended project portion.

4. Cash-out weight is consistent
The reclaim value for NFTs must match documented tier economics and must not be manipulable through discounts, credits, cross-currency inputs, or reserve timing.

5. Shared store isolation
One hook instance must not corrupt or observe mutable state belonging to another project unexpectedly.

6. Credit semantics remain bounded
Unused payment value that becomes credits must not let a user later mint tiers, trigger splits, or receive project-token issuance on terms they did not actually fund.

7. Resolver trust stays read-only unless explicitly intended
Token URI resolvers must not become an implicit control plane for mint, burn, or accounting behavior.

## Threat Model

Prioritize:
- overspending and leftover-credit edge cases
- cross-currency pricing with missing or stale feeds
- tier additions or adjustments with invalid sort order or percent bounds
- split hooks or terminal recipients that revert or partially fail
- data-hook and pay-hook interactions inside the same payment

Especially high-value attacker profiles:
- a payer crafting metadata and tier selections to desync credits, split routing, and token issuance
- a project owner adjusting tiers between preview and execution windows
- a downstream app assuming tier cash-out weight tracks discounted price when the primitive uses different economics

## Hotspots

- `beforePayRecordedWith`, `afterPayRecordedWith`, and cash-out hooks
- credit handling when `payer != beneficiary`
- discount logic versus cash-out pricing
- pending reserve minting and denominator logic
- `splitPercent` handling and hook distribution fallback behavior
- deployers that transfer ownership or queue rulesets around the hook

## Sequences Worth Replaying

1. Cross-currency payment where prices are missing, stale, or intentionally asymmetric.
2. Payment with leftover value that becomes credits, then a second payment from a different payer/beneficiary arrangement.
3. Tier purchases with split routing enabled, especially when split hooks or downstream terminals fail.
4. Reserve-heavy tiers followed by NFT cash-out before pending reserves are minted.
5. Tier adjustment or discount updates around active minting and cash-out windows.

## Build And Verification

Standard workflow:
- `npm install`
- `forge build`
- `forge test`

Current tests emphasize:
- audit and regression fixes around split accounting and cross-currency behavior
- invariants on tier lifecycle and store state
- fork coverage for ERC-20 cash-out and tier split routes

High-value findings in this repo tend to become repeatable vulnerabilities in downstream repos, so favor proofs that show the primitive itself returning or recording the wrong value.
