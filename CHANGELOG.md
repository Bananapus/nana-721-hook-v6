# Changelog

## Scope

This file describes the verified change from `nana-721-hook-v5` to the current `nana-721-hook-v6` repo.

## Current v6 surface

- `JB721TiersHook`
- `JB721TiersHookStore`
- `JB721TiersHookDeployer`
- `JB721TiersHookProjectDeployer`
- `JB721TiersHookLib`

## 0.0.70 — Active delegated vote totals

`JB721Checkpoints` now exposes the active delegated vote total:

- `getPastTotalActiveVotes(uint256 blockNumber) → uint256`
- `getTotalActiveVotes() → uint256`

These totals count voting units held by accounts with a nonzero delegate. Undelegated holders and undelegated custody addresses are excluded; if tokens return to a holder whose delegation is still set, those voting units become active again. This is separate from `getPastTierVotingUnits`, which remains the owner-based denominator for tier-scoped reward pots.

ABI change: `IJB721Checkpoints` now extends `IJBActiveVotes`.

`package.json`: version `0.0.69 → 0.0.70`, core dep `^0.0.81 → ^0.0.84`.

## 0.0.67 — Raise dependency floors to the latest published versions

Applies the dependency floor bump that 0.0.66 had to hold back. In 0.0.66 the higher `@bananapus/core-v6`
floor pushed the `JB721TiersHook` runtime bytecode past the 24,576-byte deployment size limit. An upstream
release of `@bananapus/ownable-v6` (now `0.0.36`) shrank the inherited code, so the bump now fits: with these
floors `JB721TiersHook` compiles to 24,372 bytes, 204 bytes under the limit.

Floors raised in `package.json`:

- `@bananapus/core-v6`: `^0.0.72 → ^0.0.79`
- `@bananapus/ownable-v6`: `^0.0.31 → ^0.0.36`
- `@bananapus/permission-ids-v6`: `^0.0.27 → ^0.0.29`
- `@bananapus/address-registry-v6`: `^0.0.26 → ^0.0.33`

`package.json`: version `0.0.66 → 0.0.67`.

## 0.0.66 — Document NatSpec, comment, and lint conventions in STYLE_GUIDE

Attempted to raise dependency floors to the latest published versions, but reverted the bump: with the higher
`@bananapus/core-v6` floor the `JB721TiersHook` runtime bytecode crosses the 24,576-byte deployment size limit
(it lands 175 bytes over, versus a 4-byte margin on the kept floors), so the floors are left as they were and no
dependency change ships in this release.

What does ship: `STYLE_GUIDE.md` now makes existing documentation conventions explicit. The NatSpec section
spells out the required tags for every member kind, a new Comments section codifies the "explain WHY, written as
if the current implementation is the only implementation" rule, and the Linting section states the zero
errors/warnings/notes bar that CI enforces.

`package.json`: version `0.0.65 → 0.0.66`.

## 0.0.65 — Keep the hook's no-arg view named `totalCashOutWeight()`

0.0.64 over-applied the `…Of` rename to the hook's no-arg view. The `Of` suffix is reserved for keyed getters
(`balanceOf(owner)`, `tierBalanceOf(hook, owner, tier)`, `maxTierIdOf(hook)`, the store's `totalCashOutWeightOf(hook)`);
the hook's combined cash-out-weight view takes no key, so it is reverted to **`totalCashOutWeight()`** on
`JB721Hook` / `JB721TiersHook`. The store's keyed `totalCashOutWeightOf(hook)` mapping (and the
`IJB721TiersHookStore` interface) is unchanged.

ABI: `JB721TiersHook.totalCashOutWeightOf()` → `totalCashOutWeight()` (reverting the 0.0.64 no-arg rename).
`package.json`: version `0.0.64 → 0.0.65`.

## 0.0.64 — O(1) `totalCashOutWeightOf` and `balanceOf`; rename from `totalCashOutWeight`

`JB721TiersHookStore.totalCashOutWeight` is renamed to **`totalCashOutWeightOf`** (matching the `…Of` getter
convention) and, together with `balanceOf`, is now a running aggregate maintained incrementally instead of an
O(maxTierId) loop:

- `totalCashOutWeightOf[hook]` is updated in `recordMint` (+ the tier's full price for the new outstanding NFT plus
  any newly-accrued pending reserve) and `recordBurn` (- the tier's full price). It is invariant under reserve mints
  (weight-neutral — a pending reserve becomes an outstanding NFT), tier removal (removed tiers keep their
  already-minted weight), and adding empty tiers (zero contribution).
- `balanceOf[hook][owner]` is maintained in `recordTransferForTier` (mint increments the receiver, burn decrements
  the sender, transfer does both).
- Both are now public mappings rather than view functions; the hook's no-arg `totalCashOutWeight()` view is likewise
  renamed `totalCashOutWeightOf()`.

This removes a cash-out gas-DoS: a project that delegated tier creation (e.g. via Croptop) could previously be
bricked by spamming empty tiers until `totalCashOutWeight`'s loop exceeded the block gas limit on the cash-out path
(which the terminal calls without a try/catch). `votingUnitsOf` and `totalSupplyOf` still iterate tiers, but they are
not on the cash-out fund-stranding path. A new invariant (`invariant_totalCashOutWeightMatchesRecompute`) asserts the
aggregate equals a full per-tier recompute across fuzzed operation sequences.

`package.json`: version `0.0.63 → 0.0.64`. ABI change: `totalCashOutWeight` → `totalCashOutWeightOf` on
`IJB721TiersHookStore` (and the hook's no-arg view).

## 0.0.63 — Per-tier eligible voting units checkpoint

`JB721Checkpoints` now maintains a checkpointed per-tier eligible-voting-units trace (`_tierEligibleUnitsOf`), exposed through a new external view:

- `getPastTierVotingUnits(uint256 tierId, uint256 blockNumber) → uint256` — the per-tier analogue of `getPastTotalSupply`. Distributors read it as the exact historical denominator for tier-scoped reward pots (rewards claimable only by holders of a chosen tier set).
- Write rules mirror `ownerOfAt` eligibility: a token contributes its tier voting units from the block it first gains an owner checkpoint — enrollment via `delegate(address, uint256[])` or its first transfer (the `from != address(0)` branch of `onTransfer`) — and is removed on burn.
- **Mints write nothing.** The `from == address(0)` path is skipped, so a minted-but-unenrolled token is excluded from the tier total and the mint path carries zero added checkpoint gas.

`package.json`: version `0.0.62 → 0.0.63`. No ABI breakage — this only adds the `getPastTierVotingUnits` view to `IJB721Checkpoints`.

## 0.0.50 — Bump nana-core-v6 to 0.0.53

`@bananapus/core-v6@0.0.53` ([nana-core-v6 PR #145](https://github.com/Bananapus/nana-core-v6/pull/145)) drops the `via_ir` requirement on `JBCashOutHookSpecsLib`, which lets this package consume the cross-project cashout work (`payAfterCashOutTokensOf` / `addToBalanceAfterCashOutTokensOf`) without needing `via_ir = true` in its own foundry profile. `JB721TiersHookStore.tiersOf` is not via-ir-tolerant under solc 0.8.28 (its category loop trips the Yul stack ceiling), so this dep release is what makes the bump possible at all.

- `JBPayDataHookRulesetMetadata` mirrors the new core `pauseCrossProjectFeeFreeInflows` field (bit 80 in the packed metadata word). Forwarded into the canonical `JBRulesetMetadata` at the three call sites in `JB721TiersHookProjectDeployer` (`_launchProjectFor`, `_launchRulesetsFor`, `_queueRulesetsFor`).
- All `JBRulesetMetadata` test literals patched to include `pauseCrossProjectFeeFreeInflows: false`.

`package.json`: version `0.0.49 → 0.0.50`, core dep `^0.0.48 → ^0.0.53`.

## Summary

- v6 adds tier-level split routing. `JB721TierConfig` and the surrounding minting logic now support `splitPercent` and `splits`.
- Collection metadata is more flexible than in v5. The hook can update name and symbol through the v6 metadata flow.
- Pricing context is cleaner. The hook no longer exposes prices through the old return shape, and pricing assumptions should be rebuilt from the current interfaces.
- The repo now carries a dedicated helper library to keep the hook surface manageable and to support the larger v6 feature set.
- The repo was upgraded from the v5 Solidity baseline to `0.8.28`.

## Local review remediations

- `JB721TiersHookProjectDeployer.launchRulesetsFor` now checks `LAUNCH_RULESETS` instead of `QUEUE_RULESETS`. The previous check was semantically wrong — launching active rulesets should require the launch permission, not the queue permission.

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

- New events: `SetName`, `SetSymbol`, `SplitPayoutReverted`.
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
