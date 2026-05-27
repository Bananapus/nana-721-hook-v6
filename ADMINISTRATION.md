# Administration

## At A Glance

| Item | Details |
| --- | --- |
| Scope | Tiered NFT hook configuration, tier adjustment, and deployer wiring |
| Control posture | Mixed project-owner and delegated control |
| Highest-risk actions | Adjusting tiers, setting discount or metadata behavior, and wiring the wrong hook or resolver |
| Recovery posture | Some configuration is mutable, but many tier properties are intentionally one-way |

## Purpose

`nana-721-hook-v6` splits control between project-level hook ownership and the tier rules enforced by the store. Many important settings can be changed only in limited ways after launch.

## Control Model

- project owners or delegates control hook-level configuration
- tier creation and mutation are permissioned and partially one-way
- the store trusts the calling hook for its own state namespace
- deployers package setup, but do not remove the need for runtime review

## Roles

| Role | How Assigned | Scope | Notes |
| --- | --- | --- | --- |
| Project owner | `owner()` or project control surface | Per hook | Main authority |
| Tier delegate | `JBPermissions` grant | Per project | Usually tier, mint, discount, or metadata permissions |
| Reserve beneficiary | Tier config | Per tier | Receives reserve NFTs |

## Privileged Surfaces

- `adjustTiers(...)`
- `mintFor(...)`
- `setDiscountPercentOf(...)`
- `setMetadata(...)`
- deployer setup and hook ownership transfer paths

## Deployer Permission Model

`JB721TiersHookProjectDeployer` requires callers to hold the correct Juicebox permission for each operation:

| Function | Required Permissions |
| --- | --- |
| `launchProjectFor(...)` | None (creates a new project; caller must forward any configured project creation fee) |
| `launchRulesetsFor(...)` | `LAUNCH_RULESETS` + `SET_TERMINALS` |
| `queueRulesetsOf(...)` | `QUEUE_RULESETS` |

Permissions are checked against the project owner via `_requirePermissionFrom`. The deployer calls the controller on the caller's behalf, so the controller sees the deployer as `msg.sender`.

## Immutable And One-Way

- many tier properties are immutable once created
- removed tiers do not reduce `maxTierIdOf`
- pool-like mutable rescue does not exist here; bad tier design is often expensive to unwind

## Operational Notes

- review tier parameters before launch as if they were economic policy
- treat discount changes and metadata changes as meaningful authority, not cosmetic controls
- be explicit about whether the hook participates in pay, cash out, or both
- separate resolver trust from hook and store trust

## Machine Notes

- do not reason from the hook alone when the bug may live in the store
- if a resolver is involved, inspect it separately
- if tier counts are large, re-check gas-sensitive reads and writes before operational changes

## Recovery

- some mistakes can be corrected through allowed metadata or discount changes
- many tier-design mistakes are effectively permanent once live
- deployer mistakes may require a new hook path rather than in-place repair

## Admin Boundaries

- no one can rewrite immutable tier properties after creation
- deployers do not bypass runtime permissions after setup
- resolver behavior cannot fix broken hook accounting

## Source Map

- `src/JB721TiersHook.sol`
- `src/JB721TiersHookStore.sol`
- `src/JB721TiersHookDeployer.sol`
- `src/JB721TiersHookProjectDeployer.sol`
