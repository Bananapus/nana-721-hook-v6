# 721 Hook Runtime

## Contract roles

- [`src/abstract/JB721Hook.sol`](../src/abstract/JB721Hook.sol) is the shared pay and cash-out hook surface. It validates the calling terminal, decodes metadata, and delegates runtime behavior to the concrete hook.
- [`src/JB721TiersHook.sol`](../src/JB721TiersHook.sol) is the main project-facing contract. It handles tier-aware minting, split forwarding, discount updates, metadata changes, reserve minting, and cash-out weight calculations.
- [`src/JB721TiersHookStore.sol`](../src/JB721TiersHookStore.sol) is the shared storage and accounting backend. It owns tier definitions, supply counters, burn counts, reserve availability, and voting-unit state.
- [`src/libraries/JB721TiersHookLib.sol`](../src/libraries/JB721TiersHookLib.sol) holds size-sensitive helper logic such as tier adjustment, split calculation/distribution, pricing normalization, and token-URI resolution.

## Runtime path

1. Terminal calls [`src/abstract/JB721Hook.sol`](../src/abstract/JB721Hook.sol) through the pay or cash-out hook interface.
2. The abstract hook validates the terminal and decodes metadata.
3. [`src/JB721TiersHook.sol`](../src/JB721TiersHook.sol) computes pricing, splits, credits, or burn-side cash-out weights.
4. [`src/JB721TiersHookStore.sol`](../src/JB721TiersHookStore.sol) records the mint, reserve, burn, and tier-state effects.
5. If the flow forwards split funds or resolves token metadata, the hook delegates into [`src/libraries/JB721TiersHookLib.sol`](../src/libraries/JB721TiersHookLib.sol).

## High-risk areas

- Reserve accounting: edits around `reserveFrequency`, pending reserves, or owner minting must preserve the store's supply protections.
- Tier splits: split forwarding changes affect both payer economics and project treasury accounting. Check both `beforePayRecordedWith` and the distribution path.
- Discount behavior: price discounts affect mint eligibility but cash-out weight still tracks the original tier price. Do not conflate the two.
- Voting units: verify whether a tier uses explicit voting units or falls back to price-based voting power before changing governance-facing math.
- Tier removal and cleanup: removing tiers is not the same as cleaning the sorted tier list. Storage cleanup behavior matters.
- Default reserve beneficiary changes: they affect which tiers count pending reserves unless a tier-specific beneficiary overrides it. That is an economic change, not just an admin update.

## Tests to trust first

- [`test/Fork.t.sol`](../test/Fork.t.sol) for launch and live integration flows.
- [`test/TestVotingUnitsLifecycle.t.sol`](../test/TestVotingUnitsLifecycle.t.sol) for voting-unit lifecycle behavior.
- [`test/TestCheckpoints.t.sol`](../test/TestCheckpoints.t.sol) for checkpoint/module behavior.
- [`test/invariants/TierLifecycleInvariant.t.sol`](../test/invariants/TierLifecycleInvariant.t.sol) and [`test/invariants/TieredHookStoreInvariant.t.sol`](../test/invariants/TieredHookStoreInvariant.t.sol) for store-level lifecycle invariants.
- [`test/TestSafeTransferReentrancy.t.sol`](../test/TestSafeTransferReentrancy.t.sol), [`test/721HookAttacks.t.sol`](../test/721HookAttacks.t.sol), [`test/regression/RetroactiveReserveBeneficiaryDilution.t.sol`](../test/regression/RetroactiveReserveBeneficiaryDilution.t.sol), and [`test/TestRegressionGaps.sol`](../test/TestRegressionGaps.sol) for reentrancy and attack-surface checks.
