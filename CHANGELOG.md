# V5 to V6 Changelog

## Scope

This is a V5-to-V6 migration changelog, not a package release log or commit history. It compares `nana-721-hook-v5` in `../../v5/evm` with the current `nana-721-hook-v6` repo.

## Current V6 Surface

- `JB721TiersHook`
- `JB721TiersHookStore`
- `JB721TiersHookDeployer`
- `JB721TiersHookProjectDeployer`
- `JB721Checkpoints`
- `JB721TiersHookLib`
- related interfaces, libraries, and structs under `src/`

## Current Checkpoint Reward And Membership Surfaces

`JB721Checkpoints` exposes active delegated vote totals and current-or-historical tier-membership checks used by reward
distributors:

- `getPastTotalActiveVotes(uint256 blockNumber) → uint256`
- `getTotalActiveVotes() → uint256`
- `getPastAccountTierActiveVotes(address account, uint256 tierId, uint256 blockNumber) → uint256`
- `getPastTotalTierActiveVotes(uint256 tierId, uint256 blockNumber) → uint256`
- `getTotalTierActiveVotes(uint256 tierId) → uint256`
- `hasTiersOfAt(address account, uint256[] tierIds, JB721TierOwnerMatch matchMode, uint256 blockNumber) → bool`

These totals count only voting units held by accounts with a nonzero delegate. Undelegated holders and undelegated
custody addresses are excluded; if tokens return to a holder whose delegation is still set, those voting units become
active again. Account-tier active vote history follows the holder of the tier units, not the delegate receiving voting
power.

## Package Notes

- `1.0.1`: `JB721TiersHookProjectDeployer` advertises the resolved fee payer while forwarding a project creation fee.
  It implements `IJBPayerTracker`, exposing a transient `originalPayer`, and sets it to `JBPayerTrackerLib.resolve(...)`
  around the `JBProjects.createFor` call so a `pay`-routing fee receiver credits the end user instead of the deployer.
  Bumps `@bananapus/core-v6` to `^1.0.2`.
- `0.0.76`: bounds voting-unit reads and delegation tier activation with per-owner held-tier bitmaps (one storage word
  per 256 tier IDs plus held tiers), adds current-or-historical tier-membership checks, uses checked tier-checkpoint
  downcasts, and corrects clone metadata-target comments.
- `0.0.73`: adds account-scoped per-tier active vote history for tier-scoped reward accounting.
- `0.0.72`: bumps `@bananapus/core-v6` to `^0.0.86`.
- `0.0.71`: adds per-tier active vote totals for delegated reward accounting.

## Summary

- V6 adds tier-level split routing. Tier configs can carry `splitPercent` and `splits` so part of a mint payment can be routed through Juicebox splits.
- Collection metadata is more flexible. The hook can update name and symbol through the V6 metadata flow.
- Pricing context is cleaner. `pricingContext()` no longer returns the prices contract; `PRICES()` and `SPLITS()` are explicit getters.
- Tier flags are grouped into nested flag structs, and stored tier data changed. V5 tier struct decoders are not compatible.
- The hook/store add checkpoint and aggregate surfaces used by V6 distributors and cash-out logic.

## ABI, Event, and Error Changes

- Added functions:
  - `PRICES()`
  - `SPLITS()`
  - `getPastTierVotingUnits(...)`
  - `getPastAccountTierActiveVotes(...)`
  - store aggregate getters such as `totalCashOutWeightOf(...)`
- Changed functions:
  - `pricingContext()`
  - `setMetadata(...)`
  - tier/store views that expose the changed tier structs
- Added events:
  - `SetName`
  - `SetSymbol`
  - `SplitPayoutReverted`
  - `HookDeployed`
- Changed structs:
  - `JB721TierConfig` gained split fields and nested `JB721TierConfigFlags flags`.
  - `JB721Tier` moved boolean flags into `JB721TierFlags flags`.
  - `JBStored721Tier` no longer matches the V5 packed layout.
- Added structs:
  - `JB721TierConfigFlags`
  - `JB721TierFlags`
- Added or migration-sensitive errors include:
  - `JB721TiersHookStore_SplitPercentExceedsBounds`
  - `JB721TiersHookStore_InvalidCategorySortOrder`
  - `JB721TiersHookStore_MissingReserveBeneficiary`
  - `JB721TiersHookStore_InsufficientPendingReserves`

## Machine-Checked ABI Coverage

Generated from Foundry `out/**/*.json` artifacts, filtered to this repo's own runtime source roots and excluding tests, scripts, and dependencies.

- V5 comparison package: `nana-721-hook-v5`.
- Own-source ABI artifacts compared: V6 `21`, V5 `31`.
- Contract/interface coverage: `5` added, `15` removed, `11` shared names with ABI changes, `5` shared names ABI-identical.
- Shared-name ABI item deltas: `90` added, `60` removed, `17` modified.

Added V6 ABI artifacts:
- `IJB721Checkpoints` from `src/interfaces/IJB721Checkpoints.sol`: `16` functions, `2` events, `1` errors.
- `IJB721CheckpointsDeployer` from `src/interfaces/IJB721CheckpointsDeployer.sol`: `3` functions, `0` events, `0` errors.
- `JB721Checkpoints` from `src/JB721Checkpoints.sol`: `18` functions, `3` events, `14` errors.
- `JB721CheckpointsDeployer` from `src/JB721CheckpointsDeployer.sol`: `3` functions, `0` events, `1` errors.
- `JB721TiersHookLib` from `src/libraries/JB721TiersHookLib.sol`: `3` functions, `4` events, `9` errors.

Removed V5 ABI artifacts:
- `JB721InitTiersConfig` from `src/structs/JB721InitTiersConfig.sol`: `0` functions, `0` events, `0` errors.
- `JB721Tier` from `src/structs/JB721Tier.sol`: `0` functions, `0` events, `0` errors.
- `JB721TierConfig` from `src/structs/JB721TierConfig.sol`: `0` functions, `0` events, `0` errors.
- `JB721TiersHookFlags` from `src/structs/JB721TiersHookFlags.sol`: `0` functions, `0` events, `0` errors.
- `JB721TiersMintReservesConfig` from `src/structs/JB721TiersMintReservesConfig.sol`: `0` functions, `0` events, `0` errors.
- `JB721TiersRulesetMetadata` from `src/structs/JB721TiersRulesetMetadata.sol`: `0` functions, `0` events, `0` errors.
- `JB721TiersSetDiscountPercentConfig` from `src/structs/JB721TiersSetDiscountPercentConfig.sol`: `0` functions, `0` events, `0` errors.
- `JBBitmapWord` from `src/structs/JBBitmapWord.sol`: `0` functions, `0` events, `0` errors.
- `JBDeploy721TiersHookConfig` from `src/structs/JBDeploy721TiersHookConfig.sol`: `0` functions, `0` events, `0` errors.
- `JBLaunchProjectConfig` from `src/structs/JBLaunchProjectConfig.sol`: `0` functions, `0` events, `0` errors.
- `JBLaunchRulesetsConfig` from `src/structs/JBLaunchRulesetsConfig.sol`: `0` functions, `0` events, `0` errors.
- `JBPayDataHookRulesetConfig` from `src/structs/JBPayDataHookRulesetConfig.sol`: `0` functions, `0` events, `0` errors.
- `JBPayDataHookRulesetMetadata` from `src/structs/JBPayDataHookRulesetMetadata.sol`: `0` functions, `0` events, `0` errors.
- `JBQueueRulesetsConfig` from `src/structs/JBQueueRulesetsConfig.sol`: `0` functions, `0` events, `0` errors.
- `JBStored721Tier` from `src/structs/JBStored721Tier.sol`: `0` functions, `0` events, `0` errors.

Shared ABI artifacts with changes:
- `IJB721Hook`: `2` added, `2` removed, `1` modified ABI items.
- `IJB721TiersHook`: `13` added, `7` removed, `2` modified ABI items.
- `IJB721TiersHookDeployer`: `1` added, `1` removed, `0` modified ABI items.
- `IJB721TiersHookProjectDeployer`: `3` added, `3` removed, `0` modified ABI items.
- `IJB721TiersHookStore`: `9` added, `5` removed, `5` modified ABI items.
- `JB721Constants`: `2` added, `1` removed, `0` modified ABI items.
- `JB721Hook`: `8` added, `7` removed, `1` modified ABI items.
- `JB721TiersHook`: `27` added, `17` removed, `3` modified ABI items.
- `JB721TiersHookDeployer`: `1` added, `1` removed, `0` modified ABI items.
- `JB721TiersHookProjectDeployer`: `4` added, `3` removed, `0` modified ABI items.
- `JB721TiersHookStore`: `20` added, `13` removed, `5` modified ABI items.

Generated event/error name deltas:
- Event names added:
  - `AddTier`, `DelegateChanged`, `DelegateVotesChanged`, `EIP712DomainChanged`, `RemoveTier`, `SetDefaultReserveBeneficiary`, `SetDiscountPercent`, `SetEncodedIpfsUri`.
  - `SetName`, `SetSymbol`, `SplitPayoutReverted`.
- Event names removed or replaced:
  - `AddTier`, `SetEncodedIPFSUri`.
- Error names added:
  - `CheckpointUnorderedInsertion`, `ECDSAInvalidSignature`, `ECDSAInvalidSignatureLength`, `ECDSAInvalidSignatureS`, `ERC5805FutureLookup`, `ERC6372InconsistentClock`, `InvalidAccountNonce`, `InvalidShortString`.
  - `JB721CheckpointsDeployer_Unauthorized`, `JB721Checkpoints_AlreadyInitialized`, `JB721Checkpoints_NotOwner`, `JB721Checkpoints_Unauthorized`, `JB721Hook_InvalidCashOut`, `JB721Hook_InvalidPay`, `JB721Hook_InvalidPayValue`, `JB721Hook_UnexpectedTokenCashedOut`.
  - `JB721TiersHookLib_NoTerminalForLeftover`, `JB721TiersHookLib_SplitAmountMismatch`, `JB721TiersHookLib_SplitFallbackFailed`, `JB721TiersHookLib_SplitMetadataLengthMismatch`, `JB721TiersHookLib_TokenTransferAmountMismatch`, `JB721TiersHookStore_CantMintManually`, `JB721TiersHookStore_CantRemoveTier`, `JB721TiersHookStore_DeadlockedReserve`.
  - `JB721TiersHookStore_InsufficientSupplyRemaining`, `JB721TiersHookStore_ManualMintingNotAllowed`, `JB721TiersHookStore_MissingReserveBeneficiary`, `JB721TiersHookStore_ReserveFrequencyNotAllowed`, `JB721TiersHookStore_SplitPercentExceedsBounds`, `JB721TiersHookStore_UnrecognizedTier`, `JB721TiersHookStore_VotingUnitsNotAllowed`, `JB721TiersHookStore_ZeroInitialSupply`.
  - `JB721TiersHook_CantBuyWithCredits`, `JB721TiersHook_InvalidPricingDecimals`, `JB721TiersHook_MintReserveNftsPaused`, `JB721TiersHook_MissingSplitMetadata`, `JB721TiersHook_NoProjectId`, `JB721TiersHook_Overspending`, `JB721TiersHook_TierTransfersPaused`, `JBOwnableOverrides_AddressOwnerCannotSetPermissionId`.
  - `JBOwnableOverrides_InvalidNewOwner`, `JBOwnableOverrides_ProjectDoesNotExist`, `PRBMath_MulDiv_Overflow`, `SafeCastOverflowedUintDowncast`, `SafeERC20FailedOperation`, `StringTooLong`, `VotesExpiredSignature`.
- Error names removed or replaced:
  - `JB721Hook_InvalidCashOut`, `JB721Hook_InvalidPay`, `JB721Hook_UnexpectedTokenCashedOut`, `JB721TiersHookStore_CantMintManually`, `JB721TiersHookStore_CantRemoveTier`, `JB721TiersHookStore_InsufficientSupplyRemaining`, `JB721TiersHookStore_ManualMintingNotAllowed`, `JB721TiersHookStore_ReserveFrequencyNotAllowed`.
  - `JB721TiersHookStore_UnrecognizedTier`, `JB721TiersHookStore_VotingUnitsNotAllowed`, `JB721TiersHookStore_ZeroInitialSupply`, `JB721TiersHook_MintReserveNftsPaused`, `JB721TiersHook_NoProjectId`, `JB721TiersHook_Overspending`, `JB721TiersHook_TierTransfersPaused`, `JBOwnableOverrides_InvalidNewOwner`.

Shared ABI artifacts checked with no ABI item changes:
- `ERC721`, `IJB721TokenUriResolver`, `JB721TiersRulesetMetadataResolver`, `JBBitmap`, `JBIpfsDecoder`.

## Migration Notes

- Rebuild integrations around the current `IJB721TiersHook`, store interface, and tier structs. This is not a selector-stable upgrade.
- Any indexer or frontend that decoded tier config data must account for nested flags and tier splits.
- Collection name and symbol can change, so one-time indexing at deployment is no longer enough.
