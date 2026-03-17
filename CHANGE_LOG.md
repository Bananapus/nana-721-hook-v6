# nana-721-hook-v6 Changelog (v5 → v6)

This document describes all changes between `nana-721-hook` (v5) and `nana-721-hook-v6` (v6).

---

## 1. Breaking Changes

### 1.1 `IJB721TiersHook` — Changed Function Signatures

| Function | v5 Signature | v6 Signature | Notes |
|----------|-------------|-------------|-------|
| `pricingContext()` | `returns (uint256, uint256, IJBPrices)` | `returns (uint256 currency, uint256 decimals)` | `IJBPrices` removed from return; now a separate `PRICES()` getter |
| `setMetadata(...)` | `(string baseUri, string contractMetadataUri, IJB721TokenUriResolver, uint256, bytes32)` | `(string name, string symbol, string baseUri, string contractUri, IJB721TokenUriResolver, uint256, bytes32)` | Added `name` and `symbol` parameters; `contractMetadataUri` renamed to `contractUri` |

### 1.2 `JB721Hook` (abstract) — Changed Function Signatures

| Function | v5 Signature | v6 Signature | Notes |
|----------|-------------|-------------|-------|
| `cashOutWeightOf(...)` | `(uint256[] memory, JBBeforeCashOutRecordedContext calldata) returns (uint256)` | `(uint256[] memory) returns (uint256)` | Removed `JBBeforeCashOutRecordedContext` parameter |
| `totalCashOutWeight(...)` | `(JBBeforeCashOutRecordedContext calldata) returns (uint256)` | `() returns (uint256)` | Removed `JBBeforeCashOutRecordedContext` parameter |
| `afterPayRecordedWith(...)` | Reverts if `msg.value != 0` | No `msg.value` check | v6 removes the `msg.value != 0` revert condition from pay hook validation |

### 1.3 `JB721TiersHook` — Changed Constructor

| Parameter | v5 | v6 | Notes |
|-----------|----|----|-------|
| `prices` | Not a parameter (packed in `_packedPricingContext`) | `IJBPrices prices` | Now an immutable constructor parameter |
| `splits` | Not present | `IJBSplits splits` | New immutable for tier split distribution |

### 1.4 `JB721InitTiersConfig` — Removed Field

| Field | v5 | v6 | Notes |
|-------|----|----|-------|
| `prices` | `IJBPrices prices` | Removed | Prices contract moved to `JB721TiersHook` constructor as an immutable |

### 1.5 `JB721Constants` — Renamed Constant

| v5 | v6 | Notes |
|----|----|-------|
| `MAX_DISCOUNT_PERCENT` | `DISCOUNT_DENOMINATOR` | Same value (`200`), renamed for clarity |

### 1.6 `JBStored721Tier` — Replaced Field

| Field | v5 | v6 | Notes |
|-------|----|----|-------|
| `votingUnits` (`uint32`) | Present | Removed | Replaced by `splitPercent` |
| `splitPercent` (`uint32`) | Not present | Added | Percentage of tier price routed to splits |

### 1.7 Error Signature Changes (Store)

Several store errors gained a `tierId` parameter for better debugging:

| Error | v5 | v6 |
|-------|----|----|
| `CantMintManually` | `()` | `(uint256 tierId)` |
| `CantRemoveTier` | `()` | `(uint256 tierId)` |
| `InsufficientSupplyRemaining` | `()` | `(uint256 tierId)` |
| `ManualMintingNotAllowed` | `()` | `(uint256 tierId)` |
| `ReserveFrequencyNotAllowed` | `()` | `(uint256 tierId)` |
| `UnrecognizedTier` | `()` | `(uint256 tierId)` |
| `VotingUnitsNotAllowed` | `()` | `(uint256 tierId)` |
| `ZeroInitialSupply` | `()` | `(uint256 tierId)` |

### 1.8 Solidity Version Change

All contracts upgraded from `pragma solidity 0.8.23` to `pragma solidity 0.8.26`.

---

## 2. New Features

### 2.1 Tier Splits System

The largest new feature in v6. Each tier can now define a `splitPercent` and a set of `JBSplit[]` recipients. When an NFT is minted from a tier with splits configured, a portion of the payment is routed to the tier's split group recipients instead of entering the project's balance.

**New immutables on `JB721TiersHook`:**

| Name | Type | Description |
|------|------|-------------|
| `PRICES()` | `IJBPrices` | Price feed contract (was previously packed in `_packedPricingContext`) |
| `SPLITS()` | `IJBSplits` | Splits contract for reading/writing tier split groups |

**New library: `JB721TiersHookLib`** (entirely new in v6)

Contains functions extracted from `JB721TiersHook` to stay within the EIP-170 contract size limit:

| Function | Description |
|----------|-------------|
| `adjustTiersFor(...)` | Handles tier removal, addition, event emission, and split group setting |
| `recordAddTiersFor(...)` | Records new tiers and sets their split groups (used during initialization) |
| `normalizePaymentValue(...)` | Normalizes payment value based on pricing context |
| `calculateSplitAmounts(...)` | Calculates per-tier split amounts for a pay event |
| `convertSplitAmounts(...)` | Converts split amounts between currencies |
| `calculateWeight(...)` | Adjusts minting weight to account for split amounts |
| `distributeAll(...)` | Pulls tokens and distributes forwarded funds to tier split recipients (fault-tolerant: each split wrapped in try/catch) |
| `resolveTokenURI(...)` | Resolves the token URI (moved IPFS decoding out of hook) |

**New function on `JB721TiersHook`:**

| Function | Description |
|----------|-------------|
| `executeSplitPayout(split, token, amount, projectId, groupId, decimals)` | External payable, self-call only. Executes a single split payout so the library can wrap it in try/catch. Mirrors nana-core-v6's `JBMultiTerminal.executePayout` pattern. |

**New flag on `JB721TiersHookFlags`:**

| Field | Type | Description |
|-------|------|-------------|
| `issueTokensForSplits` | `bool` | When `true`, payers receive full token credit even for the portion routed to splits. When `false` (default), weight is reduced proportionally. |

### 2.2 Mutable Collection Name and Symbol

The ERC721 collection `name` and `symbol` can now be changed after initialization via `setMetadata(...)`.

**New internal functions on `ERC721` (abstract):**

| Function | Description |
|----------|-------------|
| `_setName(string memory)` | Updates the token collection name |
| `_setSymbol(string memory)` | Updates the token collection symbol |

### 2.3 `beforePayRecordedWith` Override in `JB721TiersHook`

v6 overrides `beforePayRecordedWith` in `JB721TiersHook` (not just the base `JB721Hook`). The override calculates per-tier split amounts and adjusts the minting weight so the terminal only mints project tokens for the portion of the payment that actually enters the project. It also sets the `JBPayHookSpecification.amount` to the total split amount so the terminal forwards those funds to the hook for distribution.

### 2.4 Pricing Decimals Validation

`initialize(...)` now reverts with `JB721TiersHook_InvalidPricingDecimals` if `tiersConfig.decimals > 18`.

### 2.5 `allowSetCustomToken` Pass-Through

The `JBPayDataHookRulesetMetadata` struct gained an `allowSetCustomToken` field. In v5, the project deployer hardcoded this to `false`. In v6, it passes through the value from the config.

---

## 3. Event Changes

### 3.1 New Events on `IJB721TiersHook`

| Event | Signature | Description |
|-------|-----------|-------------|
| `SetName` | `SetName(string indexed name, address caller)` | Emitted when the collection name is changed |
| `SetSymbol` | `SetSymbol(string indexed symbol, address caller)` | Emitted when the collection symbol is changed |

| `SplitPayoutReverted` | `SplitPayoutReverted(uint256 indexed projectId, JBSplit split, uint256 amount, bytes reason, address caller)` | Emitted when a split payout reverts during distribution. Failed split's funds route to the project's balance. |

### 3.2 New Event on `IJB721TiersHookStore`

| Event | Signature | Description |
|-------|-----------|-------------|
| `SetDefaultReserveBeneficiary` | `SetDefaultReserveBeneficiary(address indexed hook, address indexed newBeneficiary, address caller)` | Emitted when the global default reserve beneficiary is changed via `useReserveBeneficiaryAsDefault` |

### 3.3 Events Unchanged

All other events (`AddPayCredits`, `AddTier`, `Mint`, `MintReservedNft`, `RemoveTier`, `SetBaseUri`, `SetContractUri`, `SetDiscountPercent`, `SetEncodedIPFSUri`, `SetTokenUriResolver`, `UsePayCredits`, `CleanTiers`, `HookDeployed`) remain identical.

---

## 4. Error Changes

### 4.1 New Errors on `JB721TiersHook`

| Error | Signature | Description |
|-------|-----------|-------------|
| `JB721TiersHook_CurrencyMismatch` | `(uint256 paymentCurrency, uint256 tierCurrency)` | Reserved for currency mismatch detection |
| `JB721TiersHook_InvalidPricingDecimals` | `(uint256 decimals)` | Reverts when `tiersConfig.decimals > 18` during initialization |

### 4.2 Store Errors with Added `tierId` Parameter

See Section 1.7 above. Eight store errors gained a `tierId` parameter for improved debuggability.

### 4.3 Errors Unchanged

All other errors (`JB721Hook_InvalidPay`, `JB721Hook_InvalidCashOut`, `JB721Hook_UnauthorizedToken`, `JB721Hook_UnexpectedTokenCashedOut`, `JB721TiersHook_AlreadyInitialized`, `JB721TiersHook_NoProjectId`, `JB721TiersHook_Overspending`, `JB721TiersHook_MintReserveNftsPaused`, `JB721TiersHook_TierTransfersPaused`) remain unchanged.

---

## 5. Struct Changes

### 5.1 `JB721Tier` — Added Field

| Field | Type | Description |
|-------|------|-------------|
| `splitPercent` | `uint32` | Percentage of the tier's price routed to the tier's split group (out of `JBConstants.SPLITS_TOTAL_PERCENT`). Inserted between `cannotIncreaseDiscountPercent` and `resolvedUri`. |

### 5.2 `JB721TierConfig` — Added Fields

| Field | Type | Description |
|-------|------|-------------|
| `splitPercent` | `uint32` | Percentage of payment routed to splits when minting from this tier |
| `splits` | `JBSplit[]` | The split recipients for this tier's split group |

### 5.3 `JBStored721Tier` — Replaced Field

The `votingUnits` (`uint32`) field was replaced by `splitPercent` (`uint32`) in the storage layout. Voting units are still tracked but no longer stored in the packed tier struct (they use the existing `_tierVotingUnitsOf` mapping).

### 5.4 `JB721InitTiersConfig` — Removed Field

| Field | Type | Description |
|-------|------|-------------|
| `prices` | `IJBPrices` | Removed. The prices contract is now an immutable on the hook itself. |

### 5.5 `JB721TiersHookFlags` — Added Field

| Field | Type | Description |
|-------|------|-------------|
| `issueTokensForSplits` | `bool` | Whether payers receive token credit for the split portion of their payment |

### 5.6 `JBPayDataHookRulesetMetadata` — Added Field

| Field | Type | Description |
|-------|------|-------------|
| `allowSetCustomToken` | `bool` | Whether the project owner can set a custom ERC-20 token. Inserted between `allowOwnerMinting` and `allowTerminalMigration`. |

### 5.7 Structs Unchanged

`JB721TiersMintReservesConfig`, `JB721TiersSetDiscountPercentConfig`, `JB721TiersRulesetMetadata`, `JBBitmapWord`, `JBDeploy721TiersHookConfig`, `JBLaunchProjectConfig`, `JBLaunchRulesetsConfig`, `JBQueueRulesetsConfig`, `JBPayDataHookRulesetConfig` remain structurally identical (import paths updated from core-v5 to core-v6).

---

## 6. Implementation Changes (Non-Interface)

### 6.1 `JB721TiersHook._processPayment` — Split Distribution

After minting NFTs and updating pay credits, v6 checks `context.hookMetadata` and `context.forwardedAmount.value`. If both are non-zero, it calls `JB721TiersHookLib.distributeAll(...)` to distribute the forwarded funds to tier split recipients. This is the core of the tier splits flow.

Split distribution is fault-tolerant: each individual split payout is executed via `this.executeSplitPayout()` wrapped in try/catch (mirroring `JBMultiTerminal.executePayout`). If any split recipient reverts, the revert is caught, a `SplitPayoutReverted` event is emitted, and the failed split's funds remain in `leftoverAmount` (which routes to the project's balance via `addToBalance`). Other splits in the same tier and subsequent tiers are unaffected.

### 6.2 `JB721TiersHook.adjustTiers` — Delegated to Library

In v5, `adjustTiers` directly called `STORE.recordRemoveTierIds()` and `STORE.recordAddTiers()` with inline event emission. In v6, the entire operation is delegated to `JB721TiersHookLib.adjustTiersFor(...)`, which also handles setting split groups for newly added tiers in `JBSplits`.

### 6.3 `JB721TiersHook.initialize` — Split Group Setup

During initialization, v6 uses `JB721TiersHookLib.recordAddTiersFor(...)` instead of calling `STORE.recordAddTiers()` directly. This also sets up split groups for tiers that have splits configured.

### 6.4 `JB721TiersHook.tokenURI` — Delegated to Library

In v5, `tokenURI` resolved the URI inline (checking the resolver, then falling back to IPFS decoding). In v6, this is delegated to `JB721TiersHookLib.resolveTokenURI(...)` to reduce contract bytecode size.

### 6.5 `JB721TiersHook._processPayment` — Payment Normalization Delegated

In v5, the payment value normalization (currency conversion via `IJBPrices`) was done inline. In v6, it is delegated to `JB721TiersHookLib.normalizePaymentValue(...)`.

### 6.6 `JB721TiersHook._packedPricingContext` — Reduced Packing

In v5, `_packedPricingContext` packed three values: currency (bits 0-31), decimals (bits 32-39), and prices contract address (bits 40-199). In v6, it only packs currency and decimals (bits 0-39) since the prices contract is now a separate immutable.

### 6.7 `JB721Hook.afterPayRecordedWith` — Removed `msg.value` Check

v5 reverted if `msg.value != 0` in `afterPayRecordedWith`. v6 removes this check because the hook now accepts forwarded native token payments for tier split distribution.

### 6.8 `JB721TiersHookStore.recordAddTiers` — Stores `splitPercent`

The store now stores `splitPercent` in the `JBStored721Tier` packed struct (replacing the `votingUnits` field in storage). The `votingUnits` value continues to be stored in the `_tierVotingUnitsOf` mapping.

### 6.9 `JB721TiersHookStore.recordAddTiers` — Emits `SetDefaultReserveBeneficiary`

When a tier config has `useReserveBeneficiaryAsDefault` set and the beneficiary differs from the current default, v6 emits the new `SetDefaultReserveBeneficiary` event.

### 6.10 `JB721TiersHookProjectDeployer` — `allowSetCustomToken` Pass-Through

In v5, the project deployer hardcoded `allowSetCustomToken: false` when constructing `JBRulesetMetadata`. In v6, it passes through `payDataRulesetConfig.metadata.allowSetCustomToken`.

---

## 7. Migration Table

### 7.1 Interfaces

| v5 | v6 | Notes |
|----|----|-------|
| `IJB721Hook` | `IJB721Hook` | Unchanged (import path updated) |
| `IJB721TiersHook` | `IJB721TiersHook` | `pricingContext()` return changed; `setMetadata()` signature changed; added `PRICES()`, `SPLITS()`, `SetName`, `SetSymbol` |
| `IJB721TiersHookDeployer` | `IJB721TiersHookDeployer` | Unchanged |
| `IJB721TiersHookProjectDeployer` | `IJB721TiersHookProjectDeployer` | Unchanged |
| `IJB721TiersHookStore` | `IJB721TiersHookStore` | Added `SetDefaultReserveBeneficiary` event; NatSpec added |
| `IJB721TokenUriResolver` | `IJB721TokenUriResolver` | Unchanged |

### 7.2 Contracts

| v5 | v6 | Notes |
|----|----|-------|
| `JB721TiersHook` | `JB721TiersHook` | Constructor gains `prices` and `splits`; tier splits system; code extracted to library |
| `JB721TiersHookDeployer` | `JB721TiersHookDeployer` | Unchanged (import paths updated) |
| `JB721TiersHookProjectDeployer` | `JB721TiersHookProjectDeployer` | `allowSetCustomToken` pass-through |
| `JB721TiersHookStore` | `JB721TiersHookStore` | `splitPercent` storage; error params added; `SetDefaultReserveBeneficiary` event |
| `JB721Hook` (abstract) | `JB721Hook` (abstract) | `cashOutWeightOf`/`totalCashOutWeight` signatures simplified; `msg.value` check removed from `afterPayRecordedWith` |
| `ERC721` (abstract) | `ERC721` (abstract) | Added `_setName()` and `_setSymbol()` |

### 7.3 Libraries

| v5 | v6 | Notes |
|----|----|-------|
| `JB721Constants` | `JB721Constants` | `MAX_DISCOUNT_PERCENT` renamed to `DISCOUNT_DENOMINATOR` |
| `JB721TiersRulesetMetadataResolver` | `JB721TiersRulesetMetadataResolver` | Unchanged |
| `JBBitmap` | `JBBitmap` | Unchanged |
| `JBIpfsDecoder` | `JBIpfsDecoder` | Unchanged |
| _(not present)_ | `JB721TiersHookLib` | New library for tier splits, payment normalization, weight calculation, and token URI resolution |

### 7.4 Structs

| v5 | v6 | Notes |
|----|----|-------|
| `JB721Tier` | `JB721Tier` | Added `splitPercent` field |
| `JB721TierConfig` | `JB721TierConfig` | Added `splitPercent` and `splits` fields |
| `JB721TiersHookFlags` | `JB721TiersHookFlags` | Added `issueTokensForSplits` field |
| `JB721InitTiersConfig` | `JB721InitTiersConfig` | Removed `prices` field |
| `JBStored721Tier` | `JBStored721Tier` | `votingUnits` replaced by `splitPercent` |
| `JBPayDataHookRulesetMetadata` | `JBPayDataHookRulesetMetadata` | Added `allowSetCustomToken` field |
| `JB721TiersMintReservesConfig` | `JB721TiersMintReservesConfig` | Unchanged |
| `JB721TiersSetDiscountPercentConfig` | `JB721TiersSetDiscountPercentConfig` | Unchanged |
| `JB721TiersRulesetMetadata` | `JB721TiersRulesetMetadata` | Unchanged |
| `JBBitmapWord` | `JBBitmapWord` | Unchanged |
| `JBDeploy721TiersHookConfig` | `JBDeploy721TiersHookConfig` | Unchanged |
| `JBLaunchProjectConfig` | `JBLaunchProjectConfig` | Unchanged |
| `JBLaunchRulesetsConfig` | `JBLaunchRulesetsConfig` | Unchanged |
| `JBQueueRulesetsConfig` | `JBQueueRulesetsConfig` | Unchanged |
| `JBPayDataHookRulesetConfig` | `JBPayDataHookRulesetConfig` | Unchanged |
