# Audit Instructions

This repo is the tiered ERC-721 hook system for Juicebox payments and NFT cash-outs. Audit it as a shared primitive used by many other repos.

## Audit Objective

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

## Start Here

1. `src/JB721TiersHookStore.sol`
2. `src/JB721TiersHook.sol`
3. `src/JB721TiersHookDeployer.sol` and `src/JB721TiersHookProjectDeployer.sol`

## Security Model

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

## Roles And Privileges

| Role | Powers | How constrained |
|------|--------|-----------------|
| Project authority | Adjust tiers, discounts, and resolver setup | Must not break supply, ordering, or accounting assumptions |
| Hook instance | Mint, burn, and compute accounting inputs | Must stay isolated from other hook instances |
| Store contract | Hold shared tier state | Must not leak or corrupt cross-project data |
| Token URI resolver | Supply metadata only | Must not become a hidden control surface |

## Integration Assumptions

| Dependency | Assumption | What breaks if wrong |
|------------|------------|----------------------|
| `nana-core-v6` | Payment and cash-out semantics remain coherent | Downstream economic routing becomes unsafe |
| Split recipients and hooks | Failures are handled in bounded ways | Mint accounting and treasury routing desync |

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

## Attack Surfaces

- `beforePayRecordedWith`, `afterPayRecordedWith`, and cash-out hooks
- credit handling when `payer != beneficiary`
- discount logic versus cash-out pricing
- pending reserve minting and denominator logic
- `splitPercent` handling and hook distribution fallback behavior
- deployers that transfer ownership or queue rulesets around the hook

Replay these sequences:
1. cross-currency payment with missing, stale, or asymmetric prices
2. leftover credits across different payer and beneficiary arrangements
3. split-routed tier purchases when downstream hooks or terminals fail
4. reserve-heavy tiers followed by NFT cash-out before reserves are minted
5. tier adjustment or discount changes around active minting and cash-out windows

## Accepted Risks Or Behaviors

- Conservative behavior is preferable to optimistic behavior because downstream repos often treat these surfaces as economic truth.

## Verification

- `npm install`
- `forge build`
- `forge test`
