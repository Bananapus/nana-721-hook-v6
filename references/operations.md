# 721 Hook Operations

## Deployment Surface

- [`src/JB721TiersHookDeployer.sol`](../src/JB721TiersHookDeployer.sol) clones and initializes hooks for existing projects.
- [`src/JB721TiersHookProjectDeployer.sol`](../src/JB721TiersHookProjectDeployer.sol) combines hook deployment with project launch or ruleset setup.
- [`script/Deploy.s.sol`](../script/Deploy.s.sol) is the deployment entry point when you need current deployment wiring rather than abstract runtime behavior.

## Change Checklist

- If you edit hook initialization, verify deployer config structs and project-launch helpers still encode the same assumptions.
- If you edit tier config or metadata behavior, inspect [`src/structs/`](../src/structs/) and the corresponding interfaces in [`src/interfaces/`](../src/interfaces/).
- If you touch permissions, verify the caller path and permission constants still line up with the downstream ecosystem package that defines them.
- If you touch URI behavior, confirm whether the issue belongs in this repo or in a downstream resolver contract that the hook calls.

## Common Failure Modes

- Payment metadata decodes to tier IDs that no longer match the intended mint path.
- Reserve or owner-mint changes accidentally violate the store's supply guarantees.
- Hook-side assumptions drift from deployer-side assumptions, especially around initialization flags and pricing context.
- A change looks metadata-only but actually changes treasury behavior because split, credit, or cash-out logic moved with it.

## Useful Proof Points

- [`test/Fork.t.sol`](../test/Fork.t.sol) for live-integration assumptions.
- [`test/TestAuditGaps.sol`](../test/TestAuditGaps.sol) for known edge cases the repo authors considered worth pinning down.
- [`test/unit/`](../test/unit/) when you need a narrow function-level proof before editing a broad runtime path.
- [`script/helpers/`](../script/helpers/) when a deployment or launch question is really about config assembly rather than contract behavior.
