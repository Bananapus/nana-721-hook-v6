# Administration

Admin privileges and their scope in nana-721-hook-v6.

## At A Glance

| Item | Details |
|------|---------|
| Scope | Per-project NFT administration for tier configuration, metadata, discounts, owner mints, and hook deployment. |
| Operators | The resolved hook owner via `JBOwnable`, project-scoped delegates through `JBPermissions`, terminals, and the deployer/store contracts. |
| Highest-risk actions | Adjusting tiers after launch, changing metadata or discounts that affect sale behavior, and deploying or initializing the wrong hook clone. |
| Recovery posture | Clone-level mistakes are usually fixed by deploying a new hook and moving future rulesets to it; immutable constructor references cannot be changed in place. |

## Routine Operations

- Grant only the specific 721 permission IDs a project operator needs instead of handing out broad owner-equivalent access.
- Use tier adjustments, metadata updates, owner mints, and discount changes with awareness of the project's current sale state and ruleset flags.
- Treat deployer and clone initialization steps as setup-only actions; verify ownership, pricing, and store references before publishing a hook address to users.
- When cash-out behavior or pay-hook composition changes, coordinate that with the project's ruleset configuration rather than assuming the hook can pause itself.

## One-Way Or High-Risk Actions

- Clone initialization is one-time, and immutable constructor references on the implementation cannot be changed afterward.
- Hook ownership transfers change who can exercise every `onlyOwner` surface; accidental ownership moves are high-impact.
- Tier and pricing changes can have user-facing economic effects immediately even when they are technically reversible for future sales.

## Recovery Notes

- If a hook is initialized with the wrong immutable dependencies or ownership model, deploy a new hook and migrate future project rulesets to it.
- If a project-specific configuration goes bad, prefer moving the project to a replacement hook over trying to retrofit behavior the hook was not designed to support.

## Roles

### Hook Owner (JBOwnable)

- **Assigned by**: `initialize()` transfers ownership to the caller. When deployed via `JB721TiersHookProjectDeployer.launchProjectFor()`, ownership is transferred to the project NFT, meaning the project owner controls the hook.
- **Scope**: Per-hook instance. Each cloned hook has its own independent owner.
- **Inheritance**: `JBOwnable` supports both EOA ownership and project-based ownership (owner = holder of the project's ERC-721 NFT). When ownership is transferred to a project via `transferOwnershipToProject()`, whoever owns that project NFT becomes the hook's owner.

### Permission Operators

- **Assigned by**: The hook owner grants permissions via the `JBPermissions` contract.
- **Scope**: Per-project. Operators can be granted specific permission IDs scoped to the hook's `PROJECT_ID`.
- **How it works**: Each privileged function calls `_requirePermissionFrom(account: owner(), projectId: PROJECT_ID, permissionId: ...)`. This passes if the caller IS the owner, OR if the caller has been granted the specified permission ID by the owner for the project.

### Terminal (Protocol-Level Caller)

- **Assigned by**: The project's `JBDirectory` configuration.
- **Scope**: Only a contract registered as a terminal for the hook's project in `JBDirectory` can call `afterPayRecordedWith()` and `afterCashOutRecordedWith()`.
- **Verification**: `DIRECTORY.isTerminalOf(projectId, IJBTerminal(msg.sender))` is checked in `JB721Hook.sol`.

### Store Callers (msg.sender Trust Model)

- **Assigned by**: Implicit. `JB721TiersHookStore` trusts `msg.sender` as the hook contract.
- **Scope**: All `record*` functions in the store use `msg.sender` as the hook address key. Any contract can call the store, but state changes are scoped to `msg.sender`'s own data namespace.
- **Why this is safe**: Each hook clone has its own address, and the store keys all data by `[msg.sender][tierId]`. A malicious contract calling the store can only modify its own namespace.

## Privileged Functions

### JB721TiersHook

| Function | Permission ID | Checked Against | What It Does |
|----------|--------------|-----------------|--------------|
| `adjustTiers()` | `ADJUST_721_TIERS` | `owner()` | Adds new tiers and/or soft-removes existing tiers. Sets tier split groups in JBSplits. |
| `mintFor()` | `MINT_721` | `owner()` | Manually mints NFTs from tiers that have `flags.allowOwnerMint` enabled. Bypasses price checks (passes `type(uint256).max` as amount). |
| `setDiscountPercentOf()` | `SET_721_DISCOUNT_PERCENT` | `owner()` | Sets the discount percentage for a single tier. |
| `setDiscountPercentsOf()` | `SET_721_DISCOUNT_PERCENT` | `owner()` | Batch-sets discount percentages for multiple tiers. |
| `setMetadata()` | `SET_721_METADATA` | `owner()` | Updates collection name, symbol, baseURI, contractURI, tokenUriResolver, and/or per-tier encoded IPFS URIs. Empty strings leave values unchanged. |
| `initialize()` | None (one-time) | `_initialized` flag check | Initializes a cloned hook. Can only be called once. Transfers ownership to caller on completion. |

### JB721TiersHookProjectDeployer

| Function | Permission ID | Checked Against | What It Does |
|----------|--------------|-----------------|--------------|
| `launchProjectFor()` | None | Anyone can call | Creates a new project with a 721 hook. Ownership goes to the specified `owner` address. |
| `launchRulesetsFor()` | `QUEUE_RULESETS` + `SET_TERMINALS` | Project NFT owner or delegate | Deploys a hook and launches rulesets for an existing project. |
| `queueRulesetsOf()` | `QUEUE_RULESETS` | Project NFT owner or delegate | Deploys a hook and queues rulesets for an existing project. |

### JB721TiersHookDeployer

| Function | Permission ID | Checked Against | What It Does |
|----------|--------------|-----------------|--------------|
| `deployHookFor()` | None | Anyone can call | Clones and initializes a new hook instance. Ownership starts with the deployer contract, then is transferred to `msg.sender`. |

### JB721Hook (Abstract Base)

| Function | Required Caller | What It Does |
|----------|----------------|--------------|
| `afterPayRecordedWith()` | Project terminal | Processes payment, mints NFTs. Verifies caller via `DIRECTORY.isTerminalOf()`. |
| `afterCashOutRecordedWith()` | Project terminal | Burns NFTs on cash out. Verifies caller via `DIRECTORY.isTerminalOf()` and that `msg.value == 0`. |

### JB721TiersHookStore (No Access Control -- msg.sender Keyed)

| Function | Caller | What It Does |
|----------|--------|--------------|
| `recordAddTiers()` | Hook contract | Adds tiers to the caller's namespace. Category sort order enforced. |
| `recordRemoveTierIds()` | Hook contract | Marks tiers as removed in bitmap. Respects `flags.cantBeRemoved` flag. |
| `recordMint()` | Hook contract | Records mints, decrements supply, enforces price and reserve checks. |
| `recordMintReservesFor()` | Hook contract | Mints reserved NFTs from a tier. |
| `recordBurn()` | Hook contract | Increments burn counter for token IDs. |
| `recordFlags()` | Hook contract | Sets behavioral flags for the caller's hook. |
| `recordSetTokenUriResolver()` | Hook contract | Sets the token URI resolver. |
| `recordSetEncodedIPFSUriOf()` | Hook contract | Sets the encoded IPFS URI for a tier. |
| `recordSetDiscountPercentOf()` | Hook contract | Updates a tier's discount percent. Enforces bounds and `flags.cantIncreaseDiscountPercent`. |
| `recordTransferForTier()` | Hook contract | Updates per-tier balance tracking on transfer. |
| `cleanTiers()` | Anyone | Reorganizes the tier sorting linked list to skip removed tiers. Pure bookkeeping, no value at risk. |

## Permission System

Permissions flow through two mechanisms:

1. **JBOwnable** (`JB721TiersHook` inherits from it): The hook has a single `owner()` that can be an EOA or a Juicebox project. When owned by a project, the holder of that project's ERC-721 NFT is the effective owner.

2. **JBPermissions** (protocol-wide permission registry): The owner can grant specific permission IDs to operator addresses. Each permission is scoped to a `(operator, account, projectId, permissionId)` tuple. The `ROOT` permission (ID 1) grants all permissions.

The `_requirePermissionFrom()` check (inherited from `JBOwnable` via `JBPermissioned`) passes if:
- `msg.sender == account` (the owner themselves), OR
- `JBPermissions.hasPermission(msg.sender, account, projectId, permissionId)` returns true.

### Permission IDs Used

| Permission ID | Constant Name | Used By |
|--------------|---------------|---------|
| `JBPermissionIds.ADJUST_721_TIERS` | `ADJUST_721_TIERS` | `adjustTiers()` |
| `JBPermissionIds.MINT_721` | `MINT_721` | `mintFor()` |
| `JBPermissionIds.SET_721_DISCOUNT_PERCENT` | `SET_721_DISCOUNT_PERCENT` | `setDiscountPercentOf()`, `setDiscountPercentsOf()` |
| `JBPermissionIds.SET_721_METADATA` | `SET_721_METADATA` | `setMetadata()` |
| `JBPermissionIds.QUEUE_RULESETS` | `QUEUE_RULESETS` | `launchRulesetsFor()`, `queueRulesetsOf()` |
| `JBPermissionIds.SET_TERMINALS` | `SET_TERMINALS` | `launchRulesetsFor()` |

## Immutable Configuration

The following are set at deploy/initialization time and **cannot be changed afterward**:

| Property | Set In | Scope |
|----------|--------|-------|
| `DIRECTORY` | Constructor | Which terminal/controller directory is trusted |
| `PRICES` | Constructor | Which prices contract is used for cross-currency conversions |
| `RULESETS` | Constructor | Which rulesets contract is consulted |
| `STORE` | Constructor | Which store manages tier data |
| `SPLITS` | Constructor | Which splits contract manages tier split groups |
| `METADATA_ID_TARGET` | Constructor | The address used for metadata ID derivation (original implementation address for clones) |
| `PROJECT_ID` | `initialize()` | Which project this hook belongs to |
| Pricing context (currency, decimals) | `initialize()` | Packed into `_packedPricingContext` -- the token denomination for tier prices |
| `JB721TiersHookFlags` | `initialize()` | `noNewTiersWithReserves`, `noNewTiersWithVotes`, `noNewTiersWithOwnerMinting`, `preventOverspending`, `issueTokensForSplits` |
| Per-tier `flags.cantBeRemoved` | `recordAddTiers()` | Whether a tier can be soft-removed |
| Per-tier `flags.cantIncreaseDiscountPercent` | `recordAddTiers()` | Whether a tier's discount can be increased |
| Per-tier `reserveFrequency` | `recordAddTiers()` | How often reserve NFTs accrue |
| Per-tier `initialSupply` | `recordAddTiers()` | Maximum number of NFTs mintable from the tier |
| Per-tier `price` | `recordAddTiers()` | The base price (and cash-out weight) of NFTs in the tier |
| Per-tier `category` | `recordAddTiers()` | The category grouping for sort order |

## Clone Pattern

`JB721TiersHook` is deployed as an implementation contract and then cloned via `LibClone.clone()` in `JB721TiersHookDeployer`. Each clone is a minimal proxy that delegates all calls to the implementation.

**Admin implications:**
- The implementation contract cannot be self-destructed or modified after deployment. Even if it could be, clones would break since they `delegatecall` to the implementation address.
- Each clone has its own storage (including `PROJECT_ID`, ownership, and tier data). The implementation's storage is unused.
- `METADATA_ID_TARGET` is set to the original implementation address, ensuring consistent metadata ID derivation across all clones.
- The `initialize()` function uses an `_initialized` bool flag to prevent re-initialization. The implementation contract's constructor sets `_initialized = true`, blocking direct initialization. Clones start with `_initialized = false` and set it to `true` during `initialize()`.

## Ruleset-Level Pauses

Two behaviors are controlled by the project's current ruleset metadata (packed into the 14-bit `metadata` field of `JBRulesetMetadata`), parsed by `JB721TiersRulesetMetadataResolver`:

| Bit | Flag | Effect |
|-----|------|--------|
| 0 | `transfersPaused` | When set, NFT transfers are blocked for tiers that have `flags.transfersPausable` enabled |
| 1 | `mintPendingReservesPaused` | When set, `mintPendingReservesFor()` reverts |

These can change each ruleset cycle, giving the project owner temporary control over these behaviors without modifying the hook itself.

## Admin Boundaries

What the hook owner **cannot** do:

- **Cannot steal or redirect existing NFTs.** The ERC-721 transfer logic is standard; the owner has no backdoor to move tokens between arbitrary addresses.
- **Cannot change tier prices after creation.** The `price` field in `JBStored721Tier` is set once in `recordAddTiers()` and never modified. Cash-out weight is always based on the original price.
- **Cannot change reserve frequency after creation.** The `reserveFrequency` is immutable per tier.
- **Cannot reduce a tier's initial supply.** Supply can only decrease through minting and burning.
- **Cannot remove a tier marked `flags.cantBeRemoved`.** The store enforces this in `recordRemoveTierIds()`.
- **Cannot increase a tier's discount if `flags.cantIncreaseDiscountPercent` is set.** The store enforces this in `recordSetDiscountPercentOf()`.
- **Cannot mint from tiers without `flags.allowOwnerMint`.** The `mintFor()` function passes `isOwnerMint: true` to the store, which checks the flag.
- **Cannot re-initialize a hook.** The `initialize()` function reverts if `_initialized` is already true.
- **Cannot change the pricing currency, decimals, or prices contract.** `PRICES` is immutable (set in constructor), and the currency/decimals in `_packedPricingContext` are set once during initialization.
- **Cannot bypass the flag restrictions.** Once `noNewTiersWithReserves`, `noNewTiersWithVotes`, or `noNewTiersWithOwnerMinting` are set, all future tiers added via `adjustTiers()` must comply.
- **Cannot mint more reserves than the formula allows.** Reserve mints are bounded by `ceil(nonReserveMints / reserveFrequency)`.
- **Cannot modify the split groups outside of `adjustTiers()`.** Tier split groups are set during tier addition via the library; there is no separate admin function to change them directly on the hook (though the project owner could call `JBSplits.setSplitGroupsOf()` directly if they have the appropriate permission).
