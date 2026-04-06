# Juicebox 721 Hook

`@bananapus/721-hook-v6` is the tiered NFT issuance layer for Juicebox V6. It lets a project mint ERC-721s on payment, attach tier-specific pricing and supply rules, mint reserves, and integrate custom token URI resolvers.

Docs: <https://docs.juicebox.money>
Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)

## Overview

This package is the standard NFT hook for the V6 ecosystem. Projects use it to:

- sell fixed-price NFT tiers through Juicebox payments
- apply tier supply, reserve frequency, voting unit, and discount rules
- cash out tiers through the Juicebox terminal surface
- compose custom metadata resolvers such as Banny or Defifa

The deployer and project-deployer helpers make it practical to clone hooks for existing projects or launch a new project with a 721 hook already configured.

Use this repo when a project's NFT logic should be part of its payment and cash-out flow. Do not use it for collection-specific rendering or game logic; those belong in higher-level packages like Banny or Defifa.

The important architectural point is that this repo does not just "mint NFTs on pay." It changes how payment value, tier state, reserves, and cash-out behavior interact.

## Key Contracts

| Contract | Role |
| --- | --- |
| `JB721TiersHook` | Main ERC-721 tiers hook that manages minting, cash outs, metadata, and ruleset-aware behavior. |
| `JB721TiersHookStore` | Shared storage contract for tier data and accounting. |
| `JB721TiersHookDeployer` | Clone factory for deploying a hook for an existing project. |
| `JB721TiersHookProjectDeployer` | Convenience deployer for launching a project with a hook already wired in. |
| `JB721Hook` | Abstract base for 721 pay and cash-out hook behavior. |

## Mental Model

Think about the repo in three pieces:

1. `JB721TiersHook` defines behavior at the project edge
2. `JB721TiersHookStore` is the tier accounting backend
3. deployers package the hook into reusable project-launch and clone flows

If a bug affects supply, reserve minting, or tier lookup, it usually lives in the hook-store interaction. If it affects project wiring, it usually lives in the deployer path or in how the hook is attached to rulesets.

The shortest useful reading order is:

1. `JB721TiersHook`
2. `JB721TiersHookStore`
3. the relevant deployer
4. the resolver plugged into the hook, if the project uses one

## Read These Files First

1. `src/JB721TiersHook.sol`
2. `src/JB721TiersHookStore.sol`
3. `src/libraries/JB721TiersHookLib.sol`
4. `src/JB721TiersHookDeployer.sol` or `src/JB721TiersHookProjectDeployer.sol`
5. the resolver contract in the downstream repo, if present

## Integration Traps

- this hook participates in treasury-facing execution, not only metadata. Teams often underestimate the economic implications of tier splits, reserve behavior, and weight adjustments.
- custom token URI resolvers should be treated as part of the project's trusted surface.
- adding a 721 hook through a deployer is easy; carrying forward the right ruleset behavior over time is where mistakes happen.
- projects should be explicit about whether the hook should affect pay, cash out, or only metadata-facing paths.

## Where State Lives

- tier definitions and accounting live primarily in `JB721TiersHookStore`
- project-facing execution and permission checks live in `JB721TiersHook`
- collection-specific presentation usually lives outside this repo in a resolver contract

That split is why UI bugs, economic bugs, and deployment bugs often land in different repos even though users describe them all as "721 hook issues."

## Install

```bash
npm install @bananapus/721-hook-v6
```

## Development

```bash
npm install
forge build
forge test
```

Useful scripts:

- `npm run deploy:mainnets`
- `npm run deploy:testnets`

## Deployment Notes

Hooks are deployed as clones and typically registered in the address registry. The package is designed to compose with Omnichain, Croptop, Defifa, Banny, and other ecosystem packages that rely on tier-aware NFT issuance.

## Repository Layout

```text
src/
  JB721TiersHook.sol
  JB721TiersHookStore.sol
  JB721TiersHookDeployer.sol
  JB721TiersHookProjectDeployer.sol
  abstract/
  interfaces/
  libraries/
  structs/
test/
  unit, E2E, fork, invariant, audit, and regression coverage
script/
  Deploy.s.sol
  helpers/
```

## Risks And Notes

- tier accounting is sensitive to reserve minting, split routing, and cross-currency normalization
- tiny split allocations can round down to zero recipient amounts; integrations should not rely on dust-sized split routing
- custom token URI resolvers are part of the security surface because they define how metadata is served
- projects need to be deliberate about whether the hook participates in pay, cash-out, or both paths
- tier mutations after launch are powerful and should be permissioned carefully

When people say "the 721 hook," they often mean three different things: the hook contract, the store, and the metadata resolver plugged into it. Audits and integrations should separate those concerns.
