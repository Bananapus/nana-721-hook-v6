# Administration

Admin privileges and their scope in nana-721-hook-v6.

## Roles

### Hook Owner (JBOwnable)

- **Assigned by**: `initialize()` transfers ownership to the caller (line 285 of `JB721TiersHook.sol`). When deployed via `JB721TiersHookProjectDeployer.launchProjectFor()`, ownership is transferred to the project NFT (line 101 of `JB721TiersHookProjectDeployer.sol`), meaning the project owner controls the hook.
- **Scope**: Per-hook instance. Each cloned hook has its own independent owner.
- **Inheritance**: `JBOwnable` supports both EOA ownership and project-based ownership (owner = holder of the project's ERC-721 NFT). When ownership is transferred to a project via `transferOwnershipToProject()`, whoever owns that project NFT becomes the hook's owner.

### Permission Operators

- **Assigned by**: The hook owner grants permissions via the `JBPermissions` contract.
- **Scope**: Per-project. Operators can be granted specific permission IDs scoped to the hook's `PROJECT_ID`.
- **How it works**: Each privileged function calls `_requirePermissionFrom(account: owner(), projectId: PROJECT_ID, permissionId: ...)`. This passes if the caller IS the owner, OR if the caller has been granted the specified permission ID by the owner for the project.

### Terminal (Protocol-Level Caller)

- **Assigned by**: The project's `JBDirectory` configuration.
- **Scope**: Only a contract registered as a terminal for the hook's project in `JBDirectory` can call `afterPayRecordedWith()` and `afterCashOutRecordedWith()`.
- **Verification**: `DIRECTORY.isTerminalOf(projectId, IJBTerminal(msg.sender))` is checked at lines 195-197 and 236-237 of `JB721Hook.sol`.

### Store Callers (msg.sender Trust Model)

- **Assigned by**: Implicit. `JB721TiersHookStore` trusts `msg.sender` as the hook contract.
- **Scope**: All `record*` functions in the store use `msg.sender` as the hook address key. Any contract can call the store, but state changes are scoped to `msg.sender`'s own data namespace.
- **Why this is safe**: Each hook clone has its own address, and the store keys all data by `[msg.sender][tierId]`. A malicious contract calling the store can only modify its own namespace.

## Privileged Functions

### JB721TiersHook

| Function | Permission ID | Checked Against | What It Does |
|----------|--------------|-----------------|--------------|
| `adjustTiers()` (line 322) | `ADJUST_721_TIERS` | `owner()` | Adds new tiers and/or soft-removes existing tiers. Sets tier split groups in JBSplits. |
| `mintFor()` (line 338) | `MINT_721` | `owner()` | Manually mints NFTs from tiers that have `allowOwnerMint` enabled. Bypasses price checks (passes `type(uint256).max` as amount). |
| `setDiscountPercentOf()` (line 389) | `SET_721_DISCOUNT_PERCENT` | `owner()` | Sets the discount percentage for a single tier. |
| `setDiscountPercentsOf()` (line 399) | `SET_721_DISCOUNT_PERCENT` | `owner()` | Batch-sets discount percentages for multiple tiers. |
| `setMetadata()` (line 420) | `SET_721_METADATA` | `owner()` | Updates baseURI, contractURI, tokenUriResolver, and/or per-tier encoded IPFS URIs. |
| `initialize()` (line 223) | None (one-time) | `PROJECT_ID == 0` check | Initializes a cloned hook. Can only be called once. Transfers ownership to caller on completion. |

### JB721TiersHookProjectDeployer

| Function | Permission ID | Checked Against | What It Does |
|----------|--------------|-----------------|--------------|
| `launchProjectFor()` (line 74) | None | Anyone can call | Creates a new project with a 721 hook. Ownership goes to the specified `owner` address. |
| `launchRulesetsFor()` (line 115) | `QUEUE_RULESETS` + `SET_TERMINALS` | Project NFT owner | Deploys a hook and launches rulesets for an existing project. |
| `queueRulesetsOf()` (line 164) | `QUEUE_RULESETS` | Project NFT owner | Deploys a hook and queues rulesets for an existing project. |

### JB721TiersHookDeployer

| Function | Permission ID | Checked Against | What It Does |
|----------|--------------|-----------------|--------------|
| `deployHookFor()` (line 68) | None | Anyone can call | Clones and initializes a new hook instance. Ownership starts with the deployer contract, then is transferred to `msg.sender`. |

### JB721Hook (Abstract Base)

| Function | Required Caller | What It Does |
|----------|----------------|--------------|
| `afterPayRecordedWith()` (line 231) | Project terminal | Processes payment, mints NFTs. Verifies caller via `DIRECTORY.isTerminalOf()`. |
| `afterCashOutRecordedWith()` (line 183) | Project terminal | Burns NFTs on cash out. Verifies caller via `DIRECTORY.isTerminalOf()` and that `msg.value == 0`. |

### JB721TiersHookStore (No Access Control -- msg.sender Keyed)

| Function | Caller | What It Does |
|----------|--------|--------------|
| `recordAddTiers()` (line 772) | Hook contract | Adds tiers to the caller's namespace. Category sort order enforced. |
| `recordRemoveTierIds()` (line 1139) | Hook contract | Marks tiers as removed in bitmap. Respects `cannotBeRemoved` flag. |
| `recordMint()` (line 1020) | Hook contract | Records mints, decrements supply, enforces price and reserve checks. |
| `recordMintReservesFor()` (line 1103) | Hook contract | Mints reserved NFTs from a tier. |
| `recordBurn()` (line 995) | Hook contract | Increments burn counter for token IDs. |
| `recordFlags()` (line 1010) | Hook contract | Sets behavioral flags for the caller's hook. |
| `recordSetTokenUriResolver()` (line 1193) | Hook contract | Sets the token URI resolver. |
| `recordSetEncodedIPFSUriOf()` (line 1187) | Hook contract | Sets the encoded IPFS URI for a tier. |
| `recordSetDiscountPercentOf()` (line 1161) | Hook contract | Updates a tier's discount percent. Enforces bounds and `cannotIncreaseDiscountPercent`. |
| `recordTransferForTier()` (line 1201) | Hook contract | Updates per-tier balance tracking on transfer. |
| `cleanTiers()` (line 726) | Anyone | Reorganizes the tier sorting linked list to skip removed tiers. Pure bookkeeping, no value at risk. |

## Permission System

Permissions flow through two mechanisms:

1. **JBOwnable** (`JB721TiersHook` inherits from it): The hook has a single `owner()` that can be an EOA or a Juicebox project. When owned by a project, the holder of that project's ERC-721 NFT is the effective owner.

2. **JBPermissions** (protocol-wide permission registry): The owner can grant specific permission IDs to operator addresses. Each permission is scoped to a `(operator, account, projectId, permissionId)` tuple. The `ROOT` permission (ID 255) grants all permissions.

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
| `RULESETS` | Constructor | Which rulesets contract is consulted |
| `STORE` | Constructor | Which store manages tier data |
| `SPLITS` | Constructor | Which splits contract manages tier split groups |
| `METADATA_ID_TARGET` | Constructor | The address used for metadata ID derivation (original implementation address for clones) |
| `PROJECT_ID` | `initialize()` | Which project this hook belongs to |
| Pricing context (currency, decimals, prices contract) | `initialize()` | Packed into `_packedPricingContext` -- the token denomination for tier prices |
| `JB721TiersHookFlags` | `initialize()` | `noNewTiersWithReserves`, `noNewTiersWithVotes`, `noNewTiersWithOwnerMinting`, `preventOverspending`, `issueTokensForSplits` |
| Per-tier `cannotBeRemoved` | `recordAddTiers()` | Whether a tier can be soft-removed |
| Per-tier `cannotIncreaseDiscountPercent` | `recordAddTiers()` | Whether a tier's discount can be increased |
| Per-tier `reserveFrequency` | `recordAddTiers()` | How often reserve NFTs accrue |
| Per-tier `initialSupply` | `recordAddTiers()` | Maximum number of NFTs mintable from the tier |
| Per-tier `price` | `recordAddTiers()` | The base price (and cash-out weight) of NFTs in the tier |
| Per-tier `category` | `recordAddTiers()` | The category grouping for sort order |

## Ruleset-Level Pauses

Two behaviors are controlled by the project's current ruleset metadata (packed into the 14-bit `metadata` field of `JBRulesetMetadata`), parsed by `JB721TiersRulesetMetadataResolver`:

| Bit | Flag | Effect |
|-----|------|--------|
| 0 | `transfersPaused` | When set, NFT transfers are blocked for tiers that have `transfersPausable` enabled |
| 1 | `mintPendingReservesPaused` | When set, `mintPendingReservesFor()` reverts |

These can change each ruleset cycle, giving the project owner temporary control over these behaviors without modifying the hook itself.

## Admin Boundaries

What the hook owner **cannot** do:

- **Cannot steal or redirect existing NFTs.** The ERC-721 transfer logic is standard; the owner has no backdoor to move tokens between arbitrary addresses.
- **Cannot change tier prices after creation.** The `price` field in `JBStored721Tier` is set once in `recordAddTiers()` and never modified. Cash-out weight is always based on the original price.
- **Cannot change reserve frequency after creation.** The `reserveFrequency` is immutable per tier.
- **Cannot reduce a tier's initial supply.** Supply can only decrease through minting and burning.
- **Cannot remove a tier marked `cannotBeRemoved`.** The store enforces this in `recordRemoveTierIds()` (line 1151).
- **Cannot increase a tier's discount if `cannotIncreaseDiscountPercent` is set.** The store enforces this in `recordSetDiscountPercentOf()` (line 1176).
- **Cannot mint from tiers without `allowOwnerMint`.** The `mintFor()` function passes `isOwnerMint: true` to the store, which checks the flag (line 1060).
- **Cannot re-initialize a hook.** The `initialize()` function reverts if `PROJECT_ID != 0` (line 237).
- **Cannot change the pricing currency or decimals.** The `_packedPricingContext` is set once during initialization.
- **Cannot bypass the flag restrictions.** Once `noNewTiersWithReserves`, `noNewTiersWithVotes`, or `noNewTiersWithOwnerMinting` are set, all future tiers added via `adjustTiers()` must comply.
- **Cannot mint more reserves than the formula allows.** Reserve mints are bounded by `ceil(nonReserveMints / reserveFrequency)`.
- **Cannot modify the split groups outside of `adjustTiers()`.** Tier split groups are set during tier addition via the library; there is no separate admin function to change them directly on the hook (though the project owner could call `JBSplits.setSplitGroupsOf()` directly if they have the appropriate permission).
