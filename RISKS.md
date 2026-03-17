# RISKS.md -- nana-721-hook-v6

## 1. Trust Assumptions

- **Store contract (`JB721TiersHookStore`) is fully trusted.** Record functions (`recordMint`, `recordBurn`, `recordAddTiers`, `recordTransferForTier`, `recordFlags`) have no access control -- they key state by `msg.sender`. Any address can call the store to manipulate state for a hook address it controls, but cannot affect other hooks.
- **Tier configuration is partially immutable.** Once created: `price`, `initialSupply`, `reserveFrequency`, `category`, `votingUnits`, `splitPercent` are permanent. Mutable: `discountPercent` (owner-controlled, subject to `cannotIncreaseDiscountPercent`), `encodedIPFSUri` (owner-controlled).
- **Category sort order is enforced only at insertion.** `recordAddTiers` reverts `InvalidCategorySortOrder` if tiers are not ascending by category. The sorted linked list (`_tierIdAfter`) depends on this invariant across all `adjustTiers` calls. Direct store callers could corrupt the list.
- **`useReserveBeneficiaryAsDefault` has global side effects.** Setting this on ANY new tier overwrites `defaultReserveBeneficiaryOf` for ALL existing tiers that lack a tier-specific `_reserveBeneficiaryOf` entry. Documented but dangerous when calling `adjustTiers` on hooks with existing tiers.
- **Clone initialization is one-shot, atomic.** `initialize()` guards via `PROJECT_ID != 0`. Deployer contracts call deploy+initialize in a single transaction, preventing front-running. Ownership transfers to `_msgSender()` at the end of `initialize`.
- **JBDirectory is trusted for terminal authentication.** `afterPayRecordedWith` and `afterCashOutRecordedWith` check `DIRECTORY.isTerminalOf()`. If the directory is compromised, arbitrary addresses can invoke pay/cashout hooks.
- **JBPrices is trusted for cross-currency conversion.** A reverting price feed blocks all payments in non-matching currencies (DoS, not fund loss). If `address(prices) == address(0)`, cross-currency payments silently skip minting.

## 2. Economic Risks

- **Cash out weight uses full undiscounted price.** `cashOutWeightOf` and `totalCashOutWeight` always use `storedTier.price`, not the discounted price. NFTs bought at a discount have cash-out value proportional to the full tier price. A `discountPercent=200` (100% off, denominator is 200) enables free minting with full cash-out weight. Mitigated by `cannotIncreaseDiscountPercent` flag.
- **Pending reserves inflate the `totalCashOutWeight` denominator.** The total includes `price * pendingReserves` for unminted reserve NFTs. This dilutes per-NFT reclaim value before reserves are actually minted. Effect is proportional to reserve frequency and number of unminted reserves.
- **Pay credits accumulate without cap.** `payCreditsOf` grows from leftover amounts after minting. Credits are per-beneficiary, not per-payer. When `payer != beneficiary`, overspend accrues to the beneficiary's credits; the payer's existing credits are not applied. No upper bound on accumulation.
- **Zero-price tiers are valid.** A tier with `price=0` allows free minting. Cash-out weight for price-0 tiers is zero, so no value extraction risk. However, they still consume supply and generate pending reserves if `reserveFrequency > 0`.
- **Discount denominator is 200, not 10,000.** `DISCOUNT_DENOMINATOR = 200`. A `discountPercent` of 1 = 0.5% off, 100 = 50% off, 200 = 100% off. `mulDiv` rounding makes small-price discounts lossy (e.g., `price=1, discountPercent=1` -> `mulDiv(1,1,200)=0`, no discount applied).
- **Currency mismatch silently skips minting.** If payment currency differs from tier pricing currency and `PRICES == address(0)`, `_processPayment` returns without minting or reverting. Funds enter the project balance, no NFTs issued, no credits created (the normalized value is 0).
- **`splitPercent` reduces minting weight.** `beforePayRecordedWith` scales down the weight returned to the terminal by `(amountValue - totalSplitAmount) / amountValue`. Payers receive fewer fungible tokens for the split portion. `issueTokensForSplits` flag overrides this to give full weight.
- **Reserved NFT minting is permissionless.** Anyone can call `mintPendingReservesFor` to mint pending reserves to the tier's beneficiary. Only gated by the `mintPendingReservesPaused` ruleset flag. Timing of reserve minting is not owner-controlled.

## 3. Reentrancy Surface

- **Split hook callbacks (`processSplitWith`).** During `afterPayRecordedWith` -> `_processPayment` -> `distributeAll`, each split payout is executed via `this.executeSplitPayout()` wrapped in try/catch. If any split recipient reverts (split hook, terminal, or beneficiary), the revert is caught, a `SplitPayoutReverted` event is emitted, and the failed split's funds stay in leftoverAmount (routed to the project's balance). Other splits proceed normally. At callback time: NFTs already minted, `payCreditsOf` updated, `remainingSupply` decremented in the store. Reentering `afterPayRecordedWith` requires terminal authentication and processes as an independent payment. Tested: `TestAuditGaps_Reentrancy` confirms reentrancy is blocked by terminal check.
- **Split beneficiary ETH sends.** Inside `executeSplitPayout`, `beneficiary.call{value: amount}("")` is used. If it returns `false`, `executeSplitPayout` returns `false` and funds stay in leftoverAmount. If it reverts, the try/catch catches it and the funds route to the project's balance. Does not revert the entire payment.
- **Terminal `.pay()` / `.addToBalanceOf()` during split distribution.** For project-targeted splits, `executeSplitPayout` calls the target project's primary terminal. The target terminal could call back into the hook, but the hook's state is fully settled (supply, credits, mint state). Reentrancy through this path cannot double-mint or corrupt state. If the terminal call reverts, try/catch catches it and funds route to the project's balance.
- **`afterCashOutRecordedWith` execution order.** Burns tokens via `_burn()` -> `_update()` -> `STORE.recordTransferForTier()` in a loop, then calls `STORE.recordBurn()`. ERC721 `_update` triggers the store's tier balance decrement. Burns go to `address(0)`, so no `onERC721Received` callback.
- **No `ReentrancyGuard`.** Protection relies entirely on state ordering (all `STORE.record*` calls before external calls) and terminal authentication checks. `_mint()` uses the non-safe variant, avoiding `onERC721Received` callbacks during minting.

## 4. Gas/DoS Vectors

- **`totalCashOutWeight` iterates ALL tier IDs** (1 to `maxTierIdOf`), including removed tiers with minted NFTs. Called during every `beforeCashOutRecordedWith`. At ~2-3k gas per tier, 500+ tiers approaches block gas limits. Could block all NFT cash-outs if an attacker with `ADJUST_721_TIERS` permission adds thousands of tiers.
- **`balanceOf`, `votingUnitsOf`, `totalSupplyOf` iterate all tiers.** Same pattern: loop from `maxTierIdOf` down to 1. These are view functions but called by governance contracts.
- **`tiersOf` traverses removed tiers.** Removed tiers are skipped via bitmap but still traversed in the linked list. `cleanTiers()` must be called separately to compact. `cleanTiers()` is permissionless and idempotent.
- **Minting from many tiers in one payment.** `recordMint` loops per tier ID: storage read (stored tier + bitmap check) per iteration. 50 tiers in one payment ~5-7M gas (tested, fits in 30M block). 100+ tiers in a single mint is feasible but consumes most of the block.
- **`recordAddTiers` sort-insertion cost.** Adding a low-category tier to a hook with many existing higher-category tiers iterates the entire sorted list to find the insertion point. O(n) per added tier.
- **Reserve minting is unbounded per call.** `mintPendingReservesFor(tierId, count)` mints `count` NFTs in a loop. Large `count` could exceed block gas. Callers should batch.
- **Max tiers capped at `uint16.max` (65,535).** Store enforces this ceiling. Practical gas limits make 1,000+ tiers problematic for on-chain reads.
- **200+ tiers tested.** `TestAuditGaps_GasLimits` adds 200 tiers and verifies store correctness and gas within 30M block limit.

## 5. Access Control

- **`adjustTiers` (add/remove):** Requires `ADJUST_721_TIERS` permission from `owner()`. Respects `noNewTiersWithReserves`, `noNewTiersWithVotes`, `noNewTiersWithOwnerMinting` flags (append-only restrictions). `cannotBeRemoved` flag on individual tiers is enforced by the store.
- **`mintFor` (owner minting):** Requires `MINT_721` permission. Bypasses price checks (`amount: type(uint256).max`). Still requires per-tier `allowOwnerMint` flag. Tiers with `reserveFrequency > 0` cannot have `allowOwnerMint` (enforced at creation).
- **`setDiscountPercentOf`:** Requires `SET_721_DISCOUNT_PERCENT` permission. Cannot increase discount if `cannotIncreaseDiscountPercent` is set on the tier. Can always decrease.
- **`setMetadata`:** Requires `SET_721_METADATA` permission. Can change name, symbol, baseURI, contractURI, tokenUriResolver, and per-tier IPFS URIs. Sentinel value `IJB721TokenUriResolver(address(this))` means "no change" for resolver.
- **Transfer pause:** Ruleset-level flag (`transfersPaused` in 721-specific metadata, bit 0). Only applies to tiers with `transfersPausable = true`. Burns (transfer to address(0)) are never paused. Tiers created with `transfersPausable = false` can never be paused.
- **`mintPendingReservesFor`:** Permissionless. Only gated by `mintPendingReservesPaused` ruleset flag (bit 1 of 721 metadata).
- **`cleanTiers`:** Permissionless, idempotent. Compacts the sorted tier list by removing gaps from deleted tiers. No economic impact.
- **Store `recordFlags`:** No access control -- stores against `msg.sender`. Safe because the store keys by caller address, but a compromised hook can freely change its own flags.

## 6. Integration Risks

- **Data hook weight override.** `beforePayRecordedWith` returns modified `weight` accounting for tier split deductions. Terminal uses this for fungible token minting. If splits consume 100% of payment, `weight = 0` and no fungible tokens are minted.
- **Metadata encoding is fragile.** Relies on `JBMetadataResolver.getDataFor` with purpose strings `"pay"` / `"cashOut"` keyed by `METADATA_ID_TARGET` (original hook deploy address for clones). Malformed metadata results in no NFTs minted (pay) or no NFTs burned (cashout) without reverting (unless `preventOverspending` is true).
- **`beforeCashOutRecordedWith` rejects fungible tokens.** Reverts with `JB721Hook_UnexpectedTokenCashedOut` if `context.cashOutCount > 0`. Cannot simultaneously cash out NFTs and fungible tokens in the same terminal call.
- **Split group ID encoding.** Composite: `uint256(uint160(hookAddress)) | (tierId << 160)`. Tier IDs are capped at uint16, so no overflow. Splits are permanently coupled to a specific hook address -- migrating to a new hook requires re-creating all split groups.
- **ERC-20 split distribution pulls from terminal.** `distributeAll` calls `SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount)` to pull ERC-20s from the terminal. Requires the terminal to have granted allowance via its `_beforeTransferTo` pattern. If the terminal's allowance mechanism changes, distribution fails.
- **ETH sent with `afterPayRecordedWith` is used for split distribution.** If no splits are configured but ETH is forwarded (non-zero `forwardedAmount`), the `hookMetadata` is empty and `distributeAll` is not called. The ETH remains in the hook contract with no recovery mechanism.
- **Token URI resolver external calls.** `tokenURI()` and `tiersOf(..., includeResolvedUri=true)` call the resolver if set. A reverting resolver blocks all metadata reads (marketplace/frontend impact, no fund risk).

## 7. Invariants to Verify

- **Per-tier supply conservation:** For every tier, `remainingSupply + outstanding + burned == initialSupply`, where `outstanding = initialSupply - remainingSupply - burned`.
- **Total cash out weight consistency:** `totalCashOutWeight >= sum(tier.price * outstandingNFTs)` for all tiers. Equality holds when no pending reserves exist. Strictly greater when pending reserves are included.
- **Reserve mints bounded by frequency:** For each tier, `reservesMinted <= ceil(nonReserveMints / reserveFrequency)`. Enforced by `_numberOfPendingReservesFor` calculation.
- **Remaining supply never exceeds initial:** `remainingSupply + numberOfBurnedFor <= initialSupply` for every tier.
- **Token ID uniqueness:** Generated as `tierId * 1_000_000_000 + tokenNumber`. Token numbers monotonically assigned from `initialSupply - remainingSupply`. Supply capped at `999,999,999` per tier. No collisions possible.
- **Credit tracking accuracy:** `payCreditsOf[addr]` equals cumulative leftover from payments where `addr` was beneficiary, minus credits consumed by subsequent mints where `payer == beneficiary`.
- **Removed tiers excluded from active listing:** `tiersOf()` never returns tiers marked in the removal bitmap.
- **`maxTierIdOf` monotonically increases:** Tier removal marks a bitmap, does not decrement `maxTierIdOf`.
- **Balance consistency:** `sum(tierBalanceOf[hook][owner][tierId])` across all tiers equals `ERC721._balances[owner]` for each owner.
- **Cash out weight uses full price regardless of discount:** `cashOutWeightOf` for any token returns the tier's stored `price`, not the discounted purchase price.
- **Discount monotonicity when locked:** If `cannotIncreaseDiscountPercent` is set, `discountPercent` can only decrease or stay the same.
- **Flags are append-only restrictions:** `noNewTiersWithReserves`, `noNewTiersWithVotes`, `noNewTiersWithOwnerMinting` prevent future tiers from using those features but do not retroactively affect existing tiers.
