# Changelog

## Scope

This file describes the verified change from `nana-721-hook-v5` to the current `nana-721-hook-v6` repo.

## Current v6 surface

- `JB721TiersHook`
- `JB721TiersHookStore`
- `JB721TiersHookDeployer`
- `JB721TiersHookProjectDeployer`
- `JB721TiersHookLib`

## Summary

- v6 adds tier-level split routing. `JB721TierConfig` and the surrounding minting logic now support `splitPercent` and `splits`.
- Collection metadata is more flexible than in v5. The hook can update name and symbol through the v6 metadata flow.
- Pricing context is cleaner. The hook no longer exposes prices through the old return shape, and pricing assumptions should be rebuilt from the current interfaces.
- The repo now carries a dedicated helper library to keep the hook surface manageable and to support the larger v6 feature set.
- The repo was upgraded from the v5 Solidity baseline to `0.8.28`.

## Verified deltas

- `IJB721TiersHook.pricingContext()` changed from a three-value return to `(currency, decimals)`.
- `IJB721TiersHook.PRICES()` is now an explicit getter instead of being bundled into `pricingContext()`.
- `IJB721TiersHook.SPLITS()` is new and matches the new tier-splits feature.
- `IJB721TiersHook.setMetadata(...)` now takes `name` and `symbol` before the URI fields.
- The interface gained new event surface around split payout failure handling and collection metadata updates.

## Breaking ABI changes

- `pricingContext()` return shape changed.
- `setMetadata(...)` argument order changed and now includes `name` and `symbol`.
- `JB721TierConfig` gained `cantBuyWithCredits`, `splitPercent`, and `splits`. Boolean flags (`allowOwnerMint`, `useReserveBeneficiaryAsDefault`, `transfersPausable`, `useVotingUnits`, `cantBeRemoved`, `cantIncreaseDiscountPercent`, `cantBuyWithCredits`) are nested in a `flags` field of type `JB721TierConfigFlags`.
- `JB721Tier` boolean flags (`allowOwnerMint`, `transfersPausable`, `cantBeRemoved`, `cantIncreaseDiscountPercent`, `cantBuyWithCredits`) are nested in a `flags` field of type `JB721TierFlags`.
- `JBStored721Tier` replaced packed `votingUnits` storage with `splitPercent` in the stored struct layout.
- `SPLITS()` and `PRICES()` are explicit interface getters.

## Indexer impact

- New events: `AddToBalanceReverted`, `SetName`, `SetSymbol`, `SplitPayoutReverted`.
- Tier config decoding changed because `JB721TierConfig` is no longer v5-compatible.
- Collection metadata can now change after deployment, so one-time indexing of `name` and `symbol` is no longer sufficient.

## Migration notes

- Rebuild integrations around the current `IJB721TiersHook` and related structs. This is not a selector-stable upgrade.
- Any indexer or frontend that decoded tier config data must account for tier splits.
- If you relied on v5 pricing-context return shapes or older metadata argument ordering, update those assumptions before shipping.

## ABI appendix

- Added functions
  - `PRICES()`
  - `SPLITS()`
- Changed functions
  - `pricingContext()`
  - `setMetadata(...)`
- Added events
  - `AddToBalanceReverted`
  - `SetName`
  - `SetSymbol`
  - `SplitPayoutReverted`
- Changed structs
  - `JB721TierConfig` (boolean flags moved to nested `JB721TierConfigFlags flags`)
  - `JB721Tier` (boolean flags moved to nested `JB721TierFlags flags`)
  - `JBStored721Tier`
- Added structs
  - `JB721TierConfigFlags`
  - `JB721TierFlags`
