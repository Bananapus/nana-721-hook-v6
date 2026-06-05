# Juicebox 721 Hook

`@bananapus/721-hook-v6` is the tiered NFT issuance layer for Juicebox V6. It lets a project mint ERC-721s on payment, attach tier-specific pricing and supply rules, mint reserves, and integrate custom token URI resolvers.

- [ARCHITECTURE.md](./ARCHITECTURE.md) — module layout, data flow, and the hook-store accounting model.
- [INVARIANTS.md](./INVARIANTS.md) — per-contract operation inventory and the guarantees the hook makes to projects and integrators.
- [ADMINISTRATION.md](./ADMINISTRATION.md) — admin surfaces, role matrix, immutable decisions, and recovery posture.
- [RISKS.md](./RISKS.md) — threat model, accepted risks, and invariants to verify.
- [USER_JOURNEYS.md](./USER_JOURNEYS.md) — example end-to-end flows for launching, paying, minting, and cashing out tiers.
- [AUDIT_INSTRUCTIONS.md](./AUDIT_INSTRUCTIONS.md) — what to focus on for a security audit and how to start.
- [SKILLS.md](./SKILLS.md) — implementation nuances, gotchas, and reading order for working on this codebase.
- [STYLE_GUIDE.md](./STYLE_GUIDE.md) — Solidity conventions and repo layout used across the V6 ecosystem.
- [CHANGELOG.md](./CHANGELOG.md) — v5 → v6 ABI and behavior deltas.
- [references/runtime.md](./references/runtime.md) — contract roles, the runtime pay and cash-out path, and high-risk areas.
- [references/operations.md](./references/operations.md) — deployment surface, change checklist, and common failure modes.

## Overview

This package is the main shared tiered NFT hook used across the V6 ecosystem. Projects use it to:

- sell fixed-price NFT tiers through Juicebox payments
- apply tier supply, reserve frequency, voting units, and discount rules
- cash out tiers through the Juicebox terminal surface
- plug in custom metadata resolvers such as Banny or Defifa

The deployer helps clone hooks for existing projects, and the project deployer helps launch new projects with a hook already attached.

Use this repo when a project's NFT logic should be part of its payment and cash-out flow. Do not use it for collection-specific rendering or game logic. Those belong in higher-level packages like Banny or Defifa.

This repo does more than "mint NFTs on pay." It changes how payment value, tier state, reserves, and cash-out behavior interact.

## Key contracts

| Contract | Role |
| --- | --- |
| `JB721TiersHook` | Main ERC-721 tiers hook that manages minting, cash outs, metadata, and ruleset-aware behavior. |
| `JB721TiersHookStore` | Shared storage contract for tier data and accounting. |
| `JB721TiersHookDeployer` | Clone factory for deploying a hook for an existing project. |
| `JB721TiersHookProjectDeployer` | Convenience deployer for launching a project with a hook already wired in. |
| `JB721Hook` | Abstract base for 721 pay and cash-out hook behavior. |
| `JB721Checkpoints` | Per-hook IVotes checkpoint module. Tracks historical owner checkpoints, per-tier eligible voting units (`getPastTierVotingUnits`) for tier-scoped reward distribution, and active delegated vote totals (`getPastTotalActiveVotes`). |

## Mental model

Think about the repo in three pieces:

1. `JB721TiersHook` defines behavior at the project edge
2. `JB721TiersHookStore` is the tier accounting backend
3. deployers package the hook into reusable launch and clone flows

If a bug affects supply, reserve minting, or tier lookup, it usually lives in the hook-store interaction. If it affects project wiring, it usually lives in the deployer path or in how the hook is attached to rulesets.

## Read these files first

1. `src/JB721TiersHook.sol`
2. `src/JB721TiersHookStore.sol`
3. `src/libraries/JB721TiersHookLib.sol`
4. `src/JB721TiersHookDeployer.sol` or `src/JB721TiersHookProjectDeployer.sol`
5. the resolver contract in the downstream repo, if present

## Integration traps

- this hook participates in treasury-facing execution, not only metadata
- custom token URI resolvers should be treated as part of the trusted surface
- adding a 721 hook through a deployer is easy; carrying the right ruleset behavior forward is where mistakes happen
- projects should be explicit about whether the hook affects pay, cash out, or only metadata-facing paths
- per-tier eligible voting units are queryable via `getPastTierVotingUnits(tierId, blockNumber)` for tier-scoped reward denominators, but minting alone does not enroll a token: a token only counts toward that total once it is enrolled (`delegate(address, uint256[])`) or transferred for the first time, and stops counting when burned
- active delegated vote totals are queryable via `getPastTotalActiveVotes(blockNumber)` and `getTotalActiveVotes()`. These totals include only voting units held by accounts with a nonzero delegate, so a token in undelegated custody does not count; this is a governance/reward-participation primitive, not the owner-based tier reward denominator.

## Where state lives

- tier definitions and accounting: `JB721TiersHookStore`
- project-facing execution and permission checks: `JB721TiersHook`
- collection-specific presentation: usually outside this repo in a resolver contract

That split is why UI bugs, economic bugs, and deployment bugs often land in different repos even when users describe them all as "721 hook issues."

## High-signal tests

1. `test/E2E/Pay_Mint_Redeem_E2E.t.sol`
2. `test/invariants/TierLifecycleInvariant.t.sol`
3. `test/invariants/TieredHookStoreInvariant.t.sol`
4. `test/regression/SplitCreditsMismatch.t.sol`
5. `test/regression/ProjectDeployerRulesets.t.sol`

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

## Deployment notes

Hooks are deployed as clones and typically registered in the address registry. The package is designed to compose with Omnichain, Croptop, Defifa, Banny, and other packages that rely on tier-aware NFT issuance.

## Repository layout

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
  unit, E2E, fork, invariant, review, and regression coverage
script/
  Deploy.s.sol
  helpers/
```

## Risks and notes

- tier accounting is sensitive to reserve minting, split routing, and cross-currency normalization
- tiny split allocations can round down to zero recipient amounts
- custom token URI resolvers are part of the security surface
- projects need to be deliberate about whether the hook participates in pay, cash out, or both paths
- tier mutations after launch are powerful and should be permissioned carefully

When people say "the 721 hook," they often mean three different things: the hook contract, the store, and the metadata resolver plugged into it.

## For AI agents

- Separate hook behavior, store behavior, and resolver behavior in your explanation.
- Read the store invariants and end-to-end pay/mint/redeem tests before summarizing lifecycle guarantees.
- If metadata or rendering behavior is project-specific, move to the downstream resolver repo.
