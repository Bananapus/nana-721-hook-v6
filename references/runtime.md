# 721 Hook Runtime

## Contract Roles

- [`src/abstract/JB721Hook.sol`](../src/abstract/JB721Hook.sol) is the shared pay and cash-out hook surface. It validates the calling terminal, decodes metadata, and delegates runtime behavior to the concrete hook.
- [`src/JB721TiersHook.sol`](../src/JB721TiersHook.sol) is the main project-facing contract. It handles tier-aware minting, split forwarding, discount updates, metadata changes, reserve minting, and cash-out weight calculations.
- [`src/JB721TiersHookStore.sol`](../src/JB721TiersHookStore.sol) is the shared storage and accounting backend. It owns tier definitions, supply counters, burn counts, reserve availability, and voting-unit state.
- [`src/libraries/JB721TiersHookLib.sol`](../src/libraries/JB721TiersHookLib.sol) holds size-sensitive helper logic such as tier adjustment, split calculation/distribution, pricing normalization, and token-URI resolution.

## Runtime Path

1. Terminal calls [`src/abstract/JB721Hook.sol`](../src/abstract/JB721Hook.sol) through the pay or cash-out hook interface.
2. The abstract hook validates the terminal and decodes metadata.
3. [`src/JB721TiersHook.sol`](../src/JB721TiersHook.sol) computes pricing, splits, credits, or burn-side cash-out weights.
4. [`src/JB721TiersHookStore.sol`](../src/JB721TiersHookStore.sol) records the mint, reserve, burn, and tier-state effects.
5. If the flow forwards split funds or resolves token metadata, the hook delegates into [`src/libraries/JB721TiersHookLib.sol`](../src/libraries/JB721TiersHookLib.sol).

## High-Risk Areas

- Reserve accounting: edits around `reserveFrequency`, pending reserves, or owner minting must preserve the store's supply protections.
- Tier splits: split forwarding changes affect both payer economics and project treasury accounting. Check both `beforePayRecordedWith` and the distribution path.
- Discount behavior: price discounts affect mint eligibility but cash-out weight still tracks the original tier price. Do not conflate the two.
- Voting units: verify whether a tier uses explicit voting units or falls back to price-based voting power before changing governance-facing math.
- Tier removal and cleanup: removing tiers is not the same as cleaning the sorted tier list. Storage cleanup behavior matters.

## Tests To Trust First

- [`test/invariants/`](../test/invariants/) for broad accounting invariants.
- [`test/E2E/`](../test/E2E/) for launch and end-to-end payment flows.
- [`test/regression/`](../test/regression/) for previously broken edge cases.
- [`test/TestVotingUnitsLifecycle.t.sol`](../test/TestVotingUnitsLifecycle.t.sol) for voting-unit lifecycle behavior.
- [`test/TestSafeTransferReentrancy.t.sol`](../test/TestSafeTransferReentrancy.t.sol) and [`test/721HookAttacks.t.sol`](../test/721HookAttacks.t.sol) for reentrancy and attack-surface checks.
