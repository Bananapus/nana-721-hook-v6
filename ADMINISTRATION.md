# Administration

## At A Glance

| Item | Details |
| --- | --- |
| Scope | Per-hook ownership, delegated 721 administration, and hook deployment flows |
| Control posture | Per-instance owner or project-owner control with delegated `JBPermissions` |
| Highest-risk actions | Tier adjustments, owner minting, metadata changes, and misassigned hook ownership |
| Recovery posture | Project-specific config can sometimes be superseded with new rulesets, but bad clone wiring usually means replacement hooks |

## Purpose

`nana-721-hook-v6` is administered per hook instance. The effective admin is the hook owner resolved through `JBOwnable`, plus any operators granted specific `JBPermissions`. The dangerous surfaces are tier adjustment, metadata changes, owner minting, discount changes, and hook deployment ownership.

## Control Model

- Each hook instance has its own owner.
- Ownership can follow an EOA or a Juicebox project NFT through `JBOwnable`.
- Fine-grained operator delegation runs through `JBPermissions`.
- Deployers are permissionless for new hooks, but existing-project launch and queue flows are permission-gated.
- The store has no owner role; it trusts `msg.sender`-keyed namespaces.

## Roles

| Role | How Assigned | Scope | Notes |
| --- | --- | --- | --- |
| Hook owner | `JBOwnable.owner()` | Per hook | May resolve dynamically through a project NFT |
| Hook operator | Granted by `JBPermissions` | Per project | Usually `ADJUST_721_TIERS`, `MINT_721`, `SET_721_METADATA`, `SET_721_DISCOUNT_PERCENT` |
| Project owner | `JBProjects.ownerOf(projectId)` | Per project | Relevant for project-deployer flows |
| Terminal | `JBDirectory` routing | Per project | Can call pay and cash-out hook entrypoints |
| Deployer caller | Anyone | Per deployment | Can deploy new standalone hooks |

## Privileged Surfaces

| Contract | Function | Who Can Call | Effect |
| --- | --- | --- | --- |
| `JB721TiersHook` | `adjustTiers(...)` | Owner or `ADJUST_721_TIERS` operator | Adds or removes tiers and updates split groups |
| `JB721TiersHook` | `mintFor(...)` | Owner or `MINT_721` operator | Owner mint path, subject to tier flags |
| `JB721TiersHook` | `setMetadata(...)` | Owner or `SET_721_METADATA` operator | Updates collection-level metadata and resolver references |
| `JB721TiersHook` | `setDiscountPercentOf(...)`, `setDiscountPercentsOf(...)` | Owner or `SET_721_DISCOUNT_PERCENT` operator | Changes discount settings where allowed |
| `JB721TiersHook` | `initialize(...)` | Anyone once per clone | One-time hook initialization and ownership setup |
| `JB721TiersHookProjectDeployer` | `launchRulesetsFor(...)` | Project owner or relevant delegates | Launches hook-backed rulesets for an existing project |
| `JB721TiersHookProjectDeployer` | `queueRulesetsOf(...)` | Project owner or `QUEUE_RULESETS` delegate | Queues hook-backed rulesets for an existing project |

## Immutable And One-Way

- Implementation constructor dependencies are immutable.
- Clone initialization is one-time.
- Per-tier price, reserve frequency, and several flags are effectively set-once semantics.
- Ownership transfers change every permission check because privileged functions check against `owner()`.

## Operational Notes

- Grant narrow per-project permissions instead of owner-equivalent access where possible.
- Treat `adjustTiers(...)` as an economic change, not just content management.
- Verify hook ownership and pricing context before publishing a clone address.
- When this hook is wrapped by deployers, review hook-order assumptions as part of administration.

## Machine Notes

- Do not assume `owner()` is a static address; it may resolve through a project NFT.
- Treat `src/JB721TiersHook.sol` and `src/JB721TiersHookStore.sol` together as the control-plane source of truth.
- If a downstream deployer changes hook ownership or ruleset ordering, re-evaluate the admin model instead of reusing old assumptions.

## Recovery

- If the wrong immutable dependencies or ownership model were deployed, use a new hook clone.
- If a project-specific configuration is bad, prefer migrating future rulesets to a replacement hook over trying to retrofit unsupported behavior.

## Admin Boundaries

- The owner cannot change the store's constructor immutables or the clone's one-time initialization.
- The owner cannot overwrite original tier price semantics used for cash-out weight.
- The owner cannot bypass store-level flags such as non-removable tiers or discount increase restrictions.
- There is no global admin who can rewrite every hook instance at once.

## Source Map

- `src/JB721TiersHook.sol`
- `src/JB721TiersHookProjectDeployer.sol`
- `src/JB721TiersHookDeployer.sol`
- `src/JB721TiersHookStore.sol`
- `script/Deploy.s.sol`
- `script/helpers/Hook721DeploymentLib.sol`
- `test/E2E/`
- `test/TestAuditGaps.sol`
