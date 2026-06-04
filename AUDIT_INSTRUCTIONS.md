# Audit Instructions

This repo adds tiered NFT issuance and cash-out behavior to Juicebox projects. Audit it as a shared accounting layer whose mistakes can affect many downstream products.

## Audit objective

There is a billion dollars of well-meaning projects' money in the Juicebox Money Engine, growing exponentially. Your job is to hack it before anyone else. Whoever hacks it first saves/steals the money, and you are obsessed with being this winner, while also being a steward of the protocol and wanting it to keep growing safely.

Suggestions of where to look:

- corrupt tier supply, reserve state, or burn accounting
- misprice cash outs or split routing
- let permissions or deployer wiring create unsafe lifecycle changes
- create gas or liveness failures in tier-heavy deployments
- break trust boundaries between hook, store, and resolver behavior

## Scope

In scope:

- `src/JB721TiersHook.sol`
- `src/JB721TiersHookStore.sol`
- deployers, libraries, interfaces, and structs under `src/`
- deployment scripts in `script/`

## Start here

1. `src/JB721TiersHook.sol`
2. `src/JB721TiersHookStore.sol`
3. `src/libraries/JB721TiersHookLib.sol`

## Security model

The hook:

- mints and burns tiered NFTs through Juicebox flows
- records tier lifecycle state in a shared store
- can route split payouts from forwarded value
- composes with project-specific metadata resolvers

## Roles and privileges

| Role | Powers | How constrained |
|------|--------|-----------------|
| Project authority | Configure tiers, metadata, and minting policy | Must stay inside explicit permission checks |
| Store caller | Mutate store state in its own namespace | Must not corrupt tier accounting |
| Resolver | Serve metadata and URI behavior | Must not be confused with accounting truth |

## Integration assumptions

| Dependency | Assumption | What breaks if wrong |
|------------|------------|----------------------|
| `nana-core-v6` | Terminal auth and pricing behavior are accurate | Pay and cash-out behavior drift |
| Resolver repo | Metadata reads behave as expected | UI and marketplace behavior break |

## Critical invariants

1. Tier supply stays coherent.  
   Remaining supply, burned counts, and outstanding ownership must reconcile.
2. Reserve logic stays bounded.  
   Pending reserves and reserve minting must not over-allocate.
3. Cash-out weight is consistent.  
   NFT reclaim value must match the tier model the hook and store intend.
4. Split and fallback behavior is safe.  
   Failed split paths must not silently corrupt value or lifecycle state.

## Attack surfaces

- pay and cash-out hook entrypoints
- tier add, remove, and clean flows
- reserve minting
- split distribution and fallback paths
- resolver integration

## Verification

- `npm install`
- `forge build`
- `forge test`
