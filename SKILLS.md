# Juicebox 721 Hook

## Use This File For

- Use this file when the task involves tiered NFT issuance, reserve minting, voting units, tier splits, or token URI resolver integration for Juicebox projects.
- Start here, then decide whether the bug is in hook runtime logic, store accounting, deployer initialization, or downstream token-URI resolution. This repo spans all four and they are easy to conflate.

## Read This Next

| If you need... | Open this next |
|---|---|
| Repo overview and integration model | [`README.md`](./README.md), [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| Runtime hook behavior | [`src/JB721TiersHook.sol`](./src/JB721TiersHook.sol), [`src/abstract/JB721Hook.sol`](./src/abstract/JB721Hook.sol) |
| Tier storage and accounting | [`src/JB721TiersHookStore.sol`](./src/JB721TiersHookStore.sol) |
| Deployment or project launch helpers | [`src/JB721TiersHookDeployer.sol`](./src/JB721TiersHookDeployer.sol), [`src/JB721TiersHookProjectDeployer.sol`](./src/JB721TiersHookProjectDeployer.sol), [`script/Deploy.s.sol`](./script/Deploy.s.sol) |
| Shared libraries, interfaces, and resolver surface | [`src/libraries/`](./src/libraries/), [`src/interfaces/`](./src/interfaces/), [`src/structs/`](./src/structs/) |
| Mint, pricing, voting, and checkpoint behavior | [`test/TestVotingUnitsLifecycle.t.sol`](./test/TestVotingUnitsLifecycle.t.sol), [`test/TestCheckpoints.t.sol`](./test/TestCheckpoints.t.sol) |
| Reentrancy, forks, and pinned edge cases | [`test/TestSafeTransferReentrancy.t.sol`](./test/TestSafeTransferReentrancy.t.sol), [`test/721HookAttacks.t.sol`](./test/721HookAttacks.t.sol), [`test/Fork.t.sol`](./test/Fork.t.sol), [`test/TestAuditGaps.sol`](./test/TestAuditGaps.sol) |

## Repo Map

| Area | Where to look |
|---|---|
| Main contracts | [`src/`](./src/) |
| Abstract bases, interfaces, structs, and libraries | [`src/abstract/`](./src/abstract/), [`src/interfaces/`](./src/interfaces/), [`src/structs/`](./src/structs/), [`src/libraries/`](./src/libraries/) |
| Scripts | [`script/`](./script/) |
| Tests | [`test/`](./test/) |

## Purpose

Tiered ERC-721 NFT issuance and cash-out hook for Juicebox V6. This repo controls tier pricing, reserve issuance, voting units, split forwarding, and deployer flows for projects that mint NFTs on pay.

## Reference Files

- Open [`references/runtime.md`](./references/runtime.md) when you need the contract roles, payment and cash-out path, reserve math, or the main invariants that should hold while editing.
- Open [`references/operations.md`](./references/operations.md) when you need deployer behavior, metadata and permission surfaces, test breadcrumbs, or the common failure modes to verify before shipping.

## Working Rules

- Start in [`src/JB721TiersHook.sol`](./src/JB721TiersHook.sol) for pay and cash-out behavior, but verify storage-side assumptions in [`src/JB721TiersHookStore.sol`](./src/JB721TiersHookStore.sol) before changing mint, burn, reserve, or supply logic.
- The store is the source of truth for supply, reserve, removal, and tier-order invariants. Do not “fix” those concepts only in the hook layer.
- Pending reserves are part of live economics, not deferred bookkeeping. Cash-out denominators and tier availability both depend on them before reserves are minted.
- Pay credits, overspending protection, and tier split forwarding are economically relevant. Treat them like accounting, not just UX.
- Treat tier splits, reserve minting, and discounted pricing as treasury-sensitive. Check both runtime code and regression coverage before assuming a change is local.
- Discounted mint price and cash-out weight are intentionally not the same thing. Free or discounted mints can still carry full tier cash-out weight by design.
- Changing the default reserve beneficiary is not cosmetic. It can change which tiers have pending reserves and therefore change redemption economics for existing mints.
- When a task mentions token metadata or rendering, confirm whether the behavior lives in this repo or in an external resolver. Do not over-edit the hook when the real change belongs downstream.
- When changing deployers or initialization, verify the hook, store, and project-launch path stay aligned. These flows are tightly coupled.
