# Juicebox 721 Hook

## Use this file for

- Use this file when the task involves tiered NFT minting, reserve minting, tier adjustments, deployer wiring, or 721-aware cash-out behavior.
- Start here, then decide whether the issue is in hook execution, store accounting, deployer setup, or resolver behavior.

## Read this next

| If you need... | Open this next |
|---|---|
| Repo overview and architecture | [`README.md`](./README.md), [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| Runtime hook behavior | [`src/JB721TiersHook.sol`](./src/JB721TiersHook.sol) |
| Tier accounting | [`src/JB721TiersHookStore.sol`](./src/JB721TiersHookStore.sol) |
| Shared math and metadata helpers | [`src/libraries/`](./src/libraries/), [`src/interfaces/`](./src/interfaces/), [`src/structs/`](./src/structs/) |
| Deployer flows | [`src/JB721TiersHookDeployer.sol`](./src/JB721TiersHookDeployer.sol), [`src/JB721TiersHookProjectDeployer.sol`](./src/JB721TiersHookProjectDeployer.sol) |
| Lifecycle, invariant, and review coverage | [`test/E2E/Pay_Mint_Redeem_E2E.t.sol`](./test/E2E/Pay_Mint_Redeem_E2E.t.sol), [`test/invariants/TierLifecycleInvariant.t.sol`](./test/invariants/TierLifecycleInvariant.t.sol), [`test/invariants/TieredHookStoreInvariant.t.sol`](./test/invariants/TieredHookStoreInvariant.t.sol), [`test/regression/SplitCreditsMismatch.t.sol`](./test/regression/SplitCreditsMismatch.t.sol) |

## Repo map

| Area | Where to look |
|---|---|
| Main contracts | [`src/`](./src/) |
| Libraries, interfaces, and structs | [`src/libraries/`](./src/libraries/), [`src/interfaces/`](./src/interfaces/), [`src/structs/`](./src/structs/) |
| Scripts | [`script/`](./script/) |
| Tests | [`test/`](./test/) |

## Purpose

Tiered NFT hook for Juicebox V6. This repo handles priced NFT tiers, reserve logic, tier-aware cash outs, and deployer flows that wire those hooks into projects.

## Reference files

- Open [`references/runtime.md`](./references/runtime.md) when you need hook and store roles, cash-out weight behavior, or main invariants.
- Open [`references/operations.md`](./references/operations.md) when you need permission paths, tier-adjustment rules, test breadcrumbs, or common stale assumptions.

## Working rules

- Start in [`src/JB721TiersHookStore.sol`](./src/JB721TiersHookStore.sol) for tier accounting questions.
- Keep hook behavior, store behavior, and resolver behavior separate.
- Reserve logic, split routing, and cash-out weight calculations are part of the economic surface.
- Tier adjustments are high-risk because many tier properties are intentionally immutable after creation.
- If a problem looks like metadata only, verify it is not actually a hook or store issue first.
