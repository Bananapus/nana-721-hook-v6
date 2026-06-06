# 721 Hook Operations

## Deployment surface

- [`src/JB721TiersHookDeployer.sol`](../src/JB721TiersHookDeployer.sol) clones and initializes hooks for existing projects.
- [`src/JB721TiersHookProjectDeployer.sol`](../src/JB721TiersHookProjectDeployer.sol) combines hook deployment with project launch or ruleset setup.
- [`script/Deploy.s.sol`](../script/Deploy.s.sol) is the deployment entry point when you need current deployment wiring rather than abstract runtime behavior.

## Change checklist

- If you edit hook initialization, verify deployer config structs and project-launch helpers still encode the same assumptions.
- If you edit tier config or metadata behavior, inspect the corresponding structs and interfaces in `src/structs/` and `src/interfaces/`.
- If you edit reserve behavior, verify pending reserve counts, default reserve beneficiary semantics, and cash-out denominator effects together.
- If you edit discount behavior, verify mint price and cash-out weight separately. They are intentionally not the same quantity.
- If you touch checkpoint, `onTransfer`, or `delegate` behavior, verify the per-tier eligible-voting-units trace (`_tierEligibleUnitsOf`, read via `getPastTierVotingUnits`) still moves only on eligibility changes: increment on mint or first checkpoint backfill, decrement on burn, and stay unchanged on ordinary transfers. Keep it in lockstep with `ownerOfAt` eligibility.
- Also verify the active delegated vote traces (`_activeSupplyCheckpoints`, `_tierActiveSupplyCheckpointsOf`, and `_accountTierActiveVotesOf`) move only when voting units enter or leave nonzero delegation. They are separate from owner-based tier reward eligibility.
- If you touch permissions, verify the caller path and permission constants still line up with the downstream ecosystem package that defines them.
- If you touch URI behavior, confirm whether the issue belongs in this repo or in a downstream resolver contract that the hook calls.

## Common failure modes

- Payment metadata decodes to tier IDs that no longer match the intended mint path.
- Reserve or owner-mint changes accidentally violate the store's supply guarantees.
- Hook-side assumptions drift from deployer-side assumptions, especially around initialization flags and pricing context.
- A change looks metadata-only but actually changes treasury behavior because split, credit, or cash-out logic moved with it.

## Useful proof points

- [`test/Fork.t.sol`](../test/Fork.t.sol) for live-integration assumptions.
- [`test/TestRegressionGaps.sol`](../test/TestRegressionGaps.sol) for known edge cases the repo authors considered worth pinning down.
- [`test/TestCheckpoints.t.sol`](../test/TestCheckpoints.t.sol) when you need a narrow function-level proof before editing a broad runtime path.
- [`test/invariants/TierLifecycleInvariant.t.sol`](../test/invariants/TierLifecycleInvariant.t.sol) and [`test/invariants/TieredHookStoreInvariant.t.sol`](../test/invariants/TieredHookStoreInvariant.t.sol) when a local patch may have broken store-level relationships.
- [`test/regression/RetroactiveReserveBeneficiaryDilution.t.sol`](../test/regression/RetroactiveReserveBeneficiaryDilution.t.sol) when reserve-beneficiary or pending-reserve behavior changes.
- [`script/Deploy.s.sol`](../script/Deploy.s.sol) when a deployment or launch question is really about config assembly rather than contract behavior.
