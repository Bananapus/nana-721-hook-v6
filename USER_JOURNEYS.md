# User Journeys -- nana-721-hook-v6

Every user-facing operation in the tiered 721 hook system, with exact entry points, parameters, state changes, events, and edge cases.

These journeys describe functional behavior, not a promise that the theoretical `uint16.max` tier ceiling is a
production-ready catalog size. Several important reads and cash-out calculations scale with `maxTierId`, so large-tier
deployments should be evaluated against the repo's documented operating envelope before launch.

---

## 1. Pay and Receive NFTs

A user pays a Juicebox project and receives tiered NFTs based on the amount paid and the tier IDs specified in metadata.

**Entry point**: `JBMultiTerminal.pay()` (external). The hook is invoked as both a data hook (`beforePayRecordedWith`) and a pay hook (`afterPayRecordedWith`).

**Parameters** (encoded in payment metadata via `JBMetadataResolver`):
- `bool allowOverspending` -- whether leftover funds after minting should be stored as credits (true) or revert (false). The hook-level `preventOverspending` flag can override this.
- `uint16[] tierIdsToMint` -- which tier IDs to mint, in order. The same tier can appear multiple times.

**Metadata encoding**: Use `JBMetadataResolver.getId({purpose: "pay", target: hook.METADATA_ID_TARGET()})` as the metadata ID. Encode the value as `abi.encode(allowOverspending, tierIdsToMint)`.

**State changes**:
1. `JBTerminalStore` records the payment with adjusted weight (reduced by split fraction unless `issueTokensForSplits` is set).
2. For each tier ID in `tierIdsToMint`:
   - `JB721TiersHookStore._storedTierOf[hook][tierId].remainingSupply` decremented by 1.
   - A new ERC-721 token is minted to the beneficiary. Token ID = `tierId * 1e9 + tokenNumber`.
   - `JB721TiersHookStore.tierBalanceOf[hook][beneficiary][tierId]` incremented by 1.
3. `payCreditsOf[beneficiary]` updated to reflect leftover amount plus unused credits.
4. If tiers have `splitPercent > 0`, forwarded funds are distributed to tier split groups via `JB721TiersHookLib.distributeAll`.

**Events**:
- `Mint(tokenId, tierId, beneficiary, totalAmountPaid, caller)` -- one per NFT minted.
- `AddPayCredits(amount, newTotalCredits, account, caller)` -- if credits increased.
- `UsePayCredits(amount, newTotalCredits, account, caller)` -- if credits decreased.

**Edge cases**:
- **No metadata or metadata not found**: No NFTs minted. If `preventOverspending` is false, the entire payment becomes credits for the beneficiary. If true, reverts.
- **Payer != beneficiary**: The payer's existing credits are NOT applied. Only the beneficiary's credits are combined with the payment. Leftover accrues to the beneficiary.
- **Tier removed**: Reverts with `JB721TiersHookStore_TierRemoved`.
- **Tier sold out**: Reverts with `JB721TiersHookStore_InsufficientSupplyRemaining`.
- **Insufficient payment**: Reverts with `JB721TiersHookStore_PriceExceedsAmount`.
- **Last slot is reserved**: If minting would leave `remainingSupply < pendingReserves`, reverts with `JB721TiersHookStore_InsufficientSupplyRemaining`.
- **Cross-currency payment with no price feed**: `normalizePaymentValue` returns `(0, false)`. The hook returns without minting or reverting. The payment is still processed by the terminal.
- **Discounted tier**: Effective price is `price - mulDiv(price, discountPercent, 200)`. A `discountPercent` of 200 makes it free.
- **Split distribution**: If a split recipient's `.call{value}` fails, the funds stay in `leftoverAmount` and are added to the project's balance.

---

## 2. Cash Out NFTs

An NFT holder burns their NFTs to reclaim funds from the project's surplus, proportional to the NFTs' cash-out weight relative to the total cash-out weight.

**Entry point**: `JBMultiTerminal.cashOutTokensOf()` (external). The hook is invoked as both a data hook (`beforeCashOutRecordedWith`) and a cash out hook (`afterCashOutRecordedWith`).

**Parameters** (encoded in cash-out metadata via `JBMetadataResolver`):
- `uint256[] tokenIds` -- the token IDs of the NFTs to burn.

**Metadata encoding**: Use `JBMetadataResolver.getId({purpose: "cashOut", target: hook.METADATA_ID_TARGET()})` as the metadata ID. Encode the value as `abi.encode(tokenIds)`.

**Preconditions**:
- The project's ruleset must have `useDataHookForCashOut` set to true.
- `cashOutCount` in the terminal call must be 0 (no fungible tokens cashed out alongside NFTs). The hook reverts with `JB721Hook_UnexpectedTokenCashedOut` otherwise.
- The caller must be the holder of all specified token IDs.

**State changes**:
1. Each NFT is burned (ERC-721 `_burn`).
2. `JB721TiersHookStore.tierBalanceOf[hook][holder][tierId]` decremented by 1 for each NFT.
3. `JB721TiersHookStore.numberOfBurnedFor[hook][tierId]` incremented by 1 for each NFT.
4. `_firstOwnerOf[tokenId]` set to `holder` if not already set (recorded during the `_update` override on burn).
5. Terminal transfers reclaim amount to beneficiary based on bonding curve math.

**Cash-out weight calculation**:
- Per-NFT weight: `storedTier.price` (original price, NOT discounted).
- Total weight: sum of `price * (mintedCount + pendingReserves)` across ALL tiers (including removed tiers).
- Reclaim amount is computed by the terminal's bonding curve using `cashOutCount / totalSupply` as the ratio.

**Events**:
- ERC-721 `Transfer(holder, address(0), tokenId)` -- one per NFT burned.

**Edge cases**:
- **Token not owned by holder**: Reverts with `JB721Hook_UnauthorizedToken`.
- **No metadata**: No token IDs decoded. No NFTs burned. Cash out weight is 0, so reclaim is 0.
- **Removed tier NFTs**: Still valid for cash out. Their weight is still counted in `totalCashOutWeight`.
- **Pending reserves inflate totalSupply**: The denominator includes unminted reserves, reducing per-NFT reclaim. This is by design.

---

## 3. Add Tiers

The project owner adds new NFT tiers to the hook.

**Entry point**: `JB721TiersHook.adjustTiers(JB721TierConfig[] calldata tiersToAdd, uint256[] calldata tierIdsToRemove)` (external).

**Permission**: `ADJUST_721_TIERS` from the hook owner.

**Parameters** (per `JB721TierConfig`):
- `uint104 price` -- tier price in the hook's pricing currency.
- `uint32 initialSupply` -- max NFTs mintable (must be > 0, <= 999,999,999).
- `uint32 votingUnits` -- custom voting power per NFT (used if `useVotingUnits` is true).
- `uint16 reserveFrequency` -- one reserve mint per N paid mints. 0 = no reserves.
- `address reserveBeneficiary` -- who receives reserve mints.
- `bytes32 encodedIPFSUri` -- IPFS CID for NFT metadata.
- `uint24 category` -- grouping category. Tiers MUST be sorted by category ascending.
- `uint8 discountPercent` -- discount out of 200 (not 100). 200 = free. Must be <= 200.
- `bool allowOwnerMint` -- allow manual owner minting from this tier.
- `bool useReserveBeneficiaryAsDefault` -- set this tier's reserve beneficiary as the global default. WARNING: overwrites the default for ALL tiers.
- `bool transfersPausable` -- whether transfers can be paused per ruleset.
- `bool useVotingUnits` -- use custom `votingUnits` instead of price for voting power.
- `bool cannotBeRemoved` -- makes this tier permanent.
- `bool cannotIncreaseDiscountPercent` -- locks the discount from being increased.
- `uint32 splitPercent` -- percentage of effective price routed to splits (out of 1,000,000,000).
- `JBSplit[] splits` -- split recipients for this tier's split group.

**State changes**:
1. New tier IDs assigned sequentially: `maxTierIdOf + 1`, `maxTierIdOf + 2`, etc.
2. `_storedTierOf[hook][tierId]` populated with a `JBStored721Tier`.
3. Sorted linked list (`_tierIdAfter`) updated to insert tiers at correct category position.
4. `_startingTierIdOfCategory[hook][category]` set for first tier in a new category.
5. `encodedIPFSUriOf[hook][tierId]` set if provided.
6. Reserve beneficiary set (per-tier or global default).
7. `maxTierIdOf[hook]` updated.
8. If any tier has `splits.length > 0`, `JBSplits.setSplitGroupsOf` is called with the tier's split group (groupId = `hookAddress | tierId << 160`, rulesetId = 0).

**Events**:
- `AddTier(tierId, tierConfig, caller)` -- one per tier added.

**Edge cases**:
- **Categories not sorted ascending**: Reverts with `JB721TiersHookStore_InvalidCategorySortOrder`.
- **Exceeds 65,535 total tiers**: Reverts with `JB721TiersHookStore_MaxTiersExceeded`.
- **`initialSupply == 0`**: Reverts with `JB721TiersHookStore_ZeroInitialSupply`.
- **`noNewTiersWithVotes` flag set**: Reverts if the new tier would have any voting power. This means tiers with `useVotingUnits = true` and `votingUnits > 0` are rejected, AND tiers with `useVotingUnits = false` and `price > 0` are also rejected (since price is used as voting power by default when `useVotingUnits` is false).
- **`noNewTiersWithReserves` flag set**: Reverts if tier has `reserveFrequency > 0`.
- **`noNewTiersWithOwnerMinting` flag set**: Reverts if tier has `allowOwnerMint = true`.
- **`allowOwnerMint` + `reserveFrequency > 0`**: Reverts with `JB721TiersHookStore_ReserveFrequencyNotAllowed`. Owner-mintable tiers cannot have reserves.
- **`useReserveBeneficiaryAsDefault = true`**: Silently overwrites `defaultReserveBeneficiaryOf[hook]`, affecting all existing tiers that use the default.

---

## 4. Remove Tiers

The project owner removes tiers, preventing new mints but preserving existing NFTs' cash-out weight.

**Entry point**: `JB721TiersHook.adjustTiers(JB721TierConfig[] calldata tiersToAdd, uint256[] calldata tierIdsToRemove)` (external). Pass an empty `tiersToAdd` array to only remove.

**Permission**: `ADJUST_721_TIERS` from the hook owner.

**Parameters**:
- `uint256[] tierIdsToRemove` -- IDs of tiers to remove.

**State changes**:
1. Each tier ID is marked in `_removedTiersBitmapWordOf[hook]` via `JBBitmap.removeTier`.
2. The stored tier data (`_storedTierOf`) is NOT deleted.
3. The sorted linked list (`_tierIdAfter`) is NOT updated. Call `cleanTiers()` separately to update it.

**Events**:
- `RemoveTier(tierId, caller)` -- one per tier removed.

**Edge cases**:
- **`cannotBeRemoved = true`**: Reverts with `JB721TiersHookStore_CantRemoveTier`.
- **Already removed tier**: No revert. Bitmap set is idempotent.
- **Existing NFTs**: Retain full cash-out weight. `totalCashOutWeight` still counts them.
- **Pending reserves**: Can still be minted from removed tiers via `mintPendingReservesFor`.

---

## 5. Mint Reserves

Anyone can mint pending reserved NFTs for a tier. Reserves accumulate based on the ratio of paid mints to the tier's `reserveFrequency`.

**Entry point**: `JB721TiersHook.mintPendingReservesFor(uint256 tierId, uint256 count)` (public, permissionless).

**Batch entry point**: `JB721TiersHook.mintPendingReservesFor(JB721TiersMintReservesConfig[] calldata reserveMintConfigs)` (external, permissionless).

**Parameters**:
- `uint256 tierId` -- the tier to mint reserves from.
- `uint256 count` -- how many reserve NFTs to mint.

**Preconditions**:
- `mintPendingReservesPaused` must be false in the current ruleset's metadata (bit 1 of `JBRulesetMetadata.metadata`).
- `count <= numberOfPendingReserves` for the tier.
- The tier must have a reserve beneficiary (tier-specific or global default).

**Pending reserve formula**:
```
nonReserveMints = initialSupply - remainingSupply - reservesMinted
pendingReserves = ceil(nonReserveMints / reserveFrequency) - reservesMinted
```

**State changes**:
1. `numberOfReservesMintedFor[hook][tierId]` incremented by `count`.
2. `_storedTierOf[hook][tierId].remainingSupply` decremented by `count`.
3. NFTs minted to `reserveBeneficiaryOf(hook, tierId)`.
4. `tierBalanceOf[hook][beneficiary][tierId]` incremented by `count`.

**Events**:
- `MintReservedNft(tokenId, tierId, beneficiary, caller)` -- one per reserve NFT minted.

**Edge cases**:
- **Paused**: Reverts with `JB721TiersHook_MintReserveNftsPaused`.
- **Count > pending**: Reverts with `JB721TiersHookStore_InsufficientPendingReserves`.
- **No reserve beneficiary**: `_numberOfPendingReservesFor` returns 0 when `reserveBeneficiaryOf` is `address(0)`. Effectively, no reserves can be minted.
- **Removed tier**: Reserves can still be minted from removed tiers.
- **Changing default beneficiary**: If the default beneficiary is changed (via `useReserveBeneficiaryAsDefault` on a new tier), pending reserves for tiers using the default are redirected to the new beneficiary.

---

## 6. Set Discount Percent

The project owner adjusts the discount on a tier's mint price. Does not affect cash-out weight.

**Entry point**: `JB721TiersHook.setDiscountPercentOf(uint256 tierId, uint256 discountPercent)` (external).

**Batch entry point**: `JB721TiersHook.setDiscountPercentsOf(JB721TiersSetDiscountPercentConfig[] calldata configs)` (external).

**Permission**: `SET_721_DISCOUNT_PERCENT` from the hook owner.

**Parameters**:
- `uint256 tierId` -- the tier to update.
- `uint256 discountPercent` -- the new discount. Out of 200 (not 100). 0 = no discount, 100 = 50% off, 200 = free.

**State changes**:
1. `_storedTierOf[hook][tierId].discountPercent` updated.

**Events**:
- `SetDiscountPercent(tierId, discountPercent, caller)`.

**Edge cases**:
- **`discountPercent > 200`**: Reverts with `JB721TiersHookStore_DiscountPercentExceedsBounds`.
- **Increasing discount when `cannotIncreaseDiscountPercent = true`**: Reverts with `JB721TiersHookStore_DiscountPercentIncreaseNotAllowed`.
- **Decreasing discount**: Always allowed, even when `cannotIncreaseDiscountPercent` is set.
- **Free mints (200)**: Effective price becomes 0. Cash-out weight still uses original price.
- **Split amounts**: `calculateSplitAmounts` uses the discounted price, so splits are proportional to what the payer actually pays.

---

## 7. Manual Owner Mint

The project owner directly mints NFTs from tiers that have `allowOwnerMint = true`, bypassing payment.

**Entry point**: `JB721TiersHook.mintFor(uint16[] calldata tierIds, address beneficiary)` (external).

**Permission**: `MINT_721` from the hook owner.

**Parameters**:
- `uint16[] tierIds` -- the tiers to mint from. One NFT per entry. Can repeat tiers.
- `address beneficiary` -- the address that receives the NFTs.

**State changes**:
1. `_storedTierOf[hook][tierId].remainingSupply` decremented by 1 per mint.
2. NFTs minted to beneficiary.
3. `tierBalanceOf[hook][beneficiary][tierId]` incremented.

**Events**:
- `Mint(tokenId, tierId, beneficiary, 0, caller)` -- `totalAmountPaid` is 0 for manual mints.

**Edge cases**:
- **`allowOwnerMint = false`**: Reverts with `JB721TiersHookStore_CantMintManually`.
- **Tier removed**: Reverts with `JB721TiersHookStore_TierRemoved`.
- **Tier sold out**: Reverts with `JB721TiersHookStore_InsufficientSupplyRemaining`.
- **Reserve supply protection**: Enforced. If minting would steal a reserved slot, reverts.
- **No price check**: `amount` is passed as `type(uint256).max`, so price validation always passes.
- **No reserve frequency allowed**: Tiers with `allowOwnerMint = true` cannot have `reserveFrequency > 0` (enforced at tier creation).

---

## 8. Adjust Tiers (Combined Add + Remove)

A single call that both adds new tiers and removes existing tiers.

**Entry point**: `JB721TiersHook.adjustTiers(JB721TierConfig[] calldata tiersToAdd, uint256[] calldata tierIdsToRemove)` (external).

**Permission**: `ADJUST_721_TIERS` from the hook owner.

**Execution order**:
1. Removals are processed first (bitmap marked).
2. Additions are processed second (new tiers stored and sorted).
3. Split groups are set for any new tiers with splits.

This ordering means a tier can be removed and a replacement tier added in the same transaction. The removed tier's ID persists; the new tier gets a fresh sequential ID.

See [Journey 3: Add Tiers](#3-add-tiers) and [Journey 4: Remove Tiers](#4-remove-tiers) for details on each operation.

---

## 9. Deploy Hook (Standalone)

Deploy a 721 tiers hook for an existing project.

**Entry point**: `JB721TiersHookDeployer.deployHookFor(uint256 projectId, JBDeploy721TiersHookConfig calldata deployTiersHookConfig, bytes32 salt)` (external).

**Parameters**:
- `uint256 projectId` -- the project to associate the hook with.
- `JBDeploy721TiersHookConfig deployTiersHookConfig`:
  - `string name` -- collection name.
  - `string symbol` -- collection symbol.
  - `string baseUri` -- base URI for IPFS token URIs.
  - `IJB721TokenUriResolver tokenUriResolver` -- custom URI resolver (or address(0)).
  - `string contractUri` -- collection-level metadata URI.
  - `JB721InitTiersConfig tiersConfig`:
    - `JB721TierConfig[] tiers` -- initial tiers (sorted by category).
    - `uint32 currency` -- pricing currency (`uint32(uint160(tokenAddress))` for concrete, or abstract like 1=ETH, 2=USD).
    - `uint8 decimals` -- pricing decimals (must be <= 18).
  - `address reserveBeneficiary` -- (unused in current initialize; set via tier configs).
  - `JB721TiersHookFlags flags` -- collection-level behavior flags.
- `bytes32 salt` -- for deterministic deployment (bytes32(0) for non-deterministic).

**State changes**:
1. A minimal proxy clone of `HOOK` is deployed (via `LibClone.clone` or `LibClone.cloneDeterministic`).
2. `initialize()` is called on the clone: sets `PROJECT_ID`, name, symbol, pricing context, tiers, flags.
3. Ownership transferred to `_msgSender()` (inside `initialize`), then to the external caller (in `deployHookFor`).
4. Clone registered with `JBAddressRegistry`.

**Events**:
- `HookDeployed(projectId, newHook, caller)`.
- `AddTier(tierId, tierConfig, caller)` -- one per initial tier.

**Edge cases**:
- **Re-initialization**: Reverts with `JB721TiersHook_AlreadyInitialized` if `PROJECT_ID` is already set.
- **`projectId == 0`**: Reverts with `JB721TiersHook_NoProjectId`.
- **`decimals > 18`**: Reverts with `JB721TiersHook_InvalidPricingDecimals`.
- **Deterministic salt collision**: Reverts at the EVM level (CREATE2 collision).
- **Implementation contract**: The original `HOOK` has `PROJECT_ID == 0`, so anyone could call `initialize` on it. However, since it is the implementation (not a clone), this would just set state on the implementation which has no operational significance -- clones do not read the implementation's storage.

---

## 10. Deploy Project + Hook

Launch a new Juicebox project with a 721 tiers hook attached, all in one transaction.

**Entry point**: `JB721TiersHookProjectDeployer.launchProjectFor(address owner, JBDeploy721TiersHookConfig calldata deployTiersHookConfig, JBLaunchProjectConfig calldata launchProjectConfig, IJBController controller, bytes32 salt)` (external).

**Parameters**:
- `address owner` -- receives the project ERC-721.
- `JBDeploy721TiersHookConfig deployTiersHookConfig` -- hook config (see Journey 9).
- `JBLaunchProjectConfig launchProjectConfig`:
  - `string projectUri` -- project metadata URI.
  - `JBPayDataHookRulesetConfig[] rulesetConfigurations` -- rulesets with `useDataHookForPay: true` hardcoded.
  - `JBTerminalConfig[] terminalConfigurations` -- which terminals to use.
  - `string memo` -- emitted in event.
- `IJBController controller` -- the controller to launch with.
- `bytes32 salt` -- for deterministic hook deployment.

**Key behavior**: `useDataHookForPay` is always set to `true` in each ruleset configuration. The deployer wraps `JBPayDataHookRulesetConfig` (which omits `useDataHookForPay` and `dataHook`) into `JBRulesetConfig` (which includes them), hardcoding the hook address as the data hook.

**State changes**:
1. Hook deployed and initialized (see Journey 9).
2. Project launched via `controller.launchProjectFor`.
3. Hook ownership transferred to the project (not the caller): `JBOwnable(hook).transferOwnershipToProject(projectId)`.

**Events**:
- All events from hook deployment (Journey 9).
- Project launch events from the controller.

**Edge cases**:
- **Project ID prediction**: Uses `DIRECTORY.PROJECTS().count() + 1` optimistically. If another project is launched in the same block before this transaction, the prediction is wrong and the call reverts.
- **Hook ownership**: Transferred to the project, meaning the project owner (ERC-721 holder) controls the hook.

---

## 11. Set Token URI Resolver

Set a custom contract that resolves token URIs for all NFTs in the collection.

**Entry point**: `JB721TiersHook.setMetadata(...)` (external). The `tokenUriResolver` parameter is an optional contract that can override the default IPFS-based token URI generation. Pass a contract address to set a custom resolver, `address(0)` to clear it and revert to the default, or the sentinel value `address(this)` to leave it unchanged.

**Permission**: `SET_721_METADATA` from the hook owner.

**Parameters** (relevant subset):
- `IJB721TokenUriResolver tokenUriResolver` -- the new resolver. Pass `IJB721TokenUriResolver(address(this))` to skip (no change). Pass `IJB721TokenUriResolver(address(0))` to clear.

**State changes**:
1. `JB721TiersHookStore.tokenUriResolverOf[hook]` updated.

**Events**:
- `SetTokenUriResolver(resolver, caller)`.

**Behavior**:
- When set, `tokenURI(tokenId)` calls `resolver.tokenUriOf(nft, tokenId)` instead of using IPFS URIs.
- When cleared (set to `address(0)`), falls back to IPFS-based URIs via `JBIpfsDecoder`.
- The sentinel value for "skip" is `address(this)` (the hook's own address), checked at line 483.

**Edge cases**:
- **Malicious resolver**: Could revert (blocking metadata reads for marketplaces) or return misleading URIs. Cannot affect funds.
- **View function only**: `tokenURI` is a view function, so resolver calls cannot modify state.

---

## 12. Clean Tiers

Reorganize the sorted tier linked list to skip removed tiers. Improves iteration efficiency.

**Entry point**: `JB721TiersHookStore.cleanTiers(address hook)` (external, permissionless).

**Parameters**:
- `address hook` -- the hook contract whose tier list to clean.

**State changes**:
1. `_tierIdAfter[hook][tierId]` mappings updated to skip removed tier IDs in the sorted sequence.

**Events**:
- `CleanTiers(hook, caller)`.

**Edge cases**:
- **Permissionless**: Anyone can call this. It is idempotent and only affects iteration ordering, not tier data or economics.
- **No removed tiers**: No-op (mappings already correct).
- **Griefing**: Repeatedly calling `cleanTiers` wastes gas but has no economic impact.

---

## 13. Set Metadata (Name, Symbol, URIs)

Update the collection's name, symbol, base URI, contract URI, or per-tier IPFS URI.

**Entry point**: `JB721TiersHook.setMetadata(string calldata name, string calldata symbol, string calldata baseUri, string calldata contractUri, IJB721TokenUriResolver tokenUriResolver, uint256 encodedIPFSUriTierId, bytes32 encodedIPFSUri)` (external).

**Permission**: `SET_721_METADATA` from the hook owner.

**Parameters**:
- `string name` -- new collection name. Empty string = no change.
- `string symbol` -- new collection symbol. Empty string = no change.
- `string baseUri` -- new base URI. Empty string = no change.
- `string contractUri` -- new contract URI. Empty string = no change.
- `IJB721TokenUriResolver tokenUriResolver` -- new URI resolver. `address(this)` = no change. `address(0)` = clear.
- `uint256 encodedIPFSUriTierId` -- tier ID to update IPFS URI for. 0 = no change.
- `bytes32 encodedIPFSUri` -- new encoded IPFS URI. `bytes32(0)` = no change (combined with tierId == 0).

**State changes**:
1. `ERC721._name` and/or `ERC721._symbol` updated (if non-empty).
2. `baseURI` updated (if non-empty).
3. `contractURI` updated (if non-empty).
4. `tokenUriResolverOf[hook]` updated (if not sentinel).
5. `encodedIPFSUriOf[hook][tierId]` updated (if both tierId != 0 and encodedIPFSUri != bytes32(0)).

**Events**:
- `SetName(name, caller)` -- if name changed.
- `SetSymbol(symbol, caller)` -- if symbol changed.
- `SetBaseUri(baseUri, caller)` -- if base URI changed.
- `SetContractUri(uri, caller)` -- if contract URI changed.
- `SetTokenUriResolver(resolver, caller)` -- if resolver changed.
- `SetEncodedIPFSUri(tierId, encodedUri, caller)` -- if IPFS URI changed.

---

## 14. Transfer NFT

Transfer an NFT between addresses. Subject to per-tier and per-ruleset pause controls.

**Entry point**: Standard ERC-721 `transferFrom(address from, address to, uint256 tokenId)` or `safeTransferFrom(...)`.

**Permission**: Standard ERC-721 (owner, approved, or operator).

**State changes**:
1. ERC-721 ownership updated.
2. `JB721TiersHookStore.tierBalanceOf[hook][from][tierId]` decremented.
3. `JB721TiersHookStore.tierBalanceOf[hook][to][tierId]` incremented.
4. `_firstOwnerOf[tokenId]` set to `from` (if not already set and `from != address(0)`).

**Transfer pause check** (in `_update` override):
1. Look up the tier via `STORE.tierOfTokenId(hook, tokenId, false)`.
2. If `tier.transfersPausable == true`:
   - Fetch current ruleset via `RULESETS.currentOf(PROJECT_ID)`.
   - Check `JB721TiersRulesetMetadataResolver.transfersPaused(metadata)` (bit 0).
   - If paused and `to != address(0)` (not a burn): revert with `JB721TiersHook_TierTransfersPaused`.

**Events**:
- ERC-721 `Transfer(from, to, tokenId)`.

**Edge cases**:
- **Tier has `transfersPausable = false`**: Transfers can never be paused for this tier, regardless of ruleset settings.
- **Burns (to == address(0))**: Never blocked by transfer pause. Burns always go through.
- **Mints (from == address(0))**: The pause check is skipped for mints (`from != address(0)` guard).
- **Cross-contract call**: Every transfer triggers `STORE.recordTransferForTier` to update `tierBalanceOf`.

---

## 15. Set Splits for Tiers

Configure how a percentage of a tier's effective price is distributed to split recipients when NFTs are minted from that tier.

**Entry point**: Splits are set during tier creation via `adjustTiers` (see Journey 3). The `splits` field in `JB721TierConfig` defines the split recipients.

**Split group ID**: `uint256(uint160(hookAddress)) | (uint256(tierId) << 160)`. This is stored in `JBSplits` with `rulesetId = 0` (always active).

**How it works during payment**:
1. `beforePayRecordedWith` calls `JB721TiersHookLib.calculateSplitAmounts` to compute per-tier split amounts based on `effectivePrice * splitPercent / SPLITS_TOTAL_PERCENT`.
2. The `totalSplitAmount` is forwarded to the hook via `hookSpecifications[0].amount`.
3. The terminal reduces the project's recorded balance by the split amount.
4. `afterPayRecordedWith` calls `JB721TiersHookLib.distributeAll` to distribute the forwarded funds.
5. Each tier's split group is read from `JBSplits` and distributed via `_distributeSingleSplit`.
6. Leftover (from rounding or splits with no valid recipient) is added back to the project's balance.

**Split recipient priority**: `split.hook` > `split.projectId` > `split.beneficiary`. If none are set, the split's share stays as leftover and goes to the project's balance.

**Parameters** (per `JBSplit`):
- `bool preferAddToBalance` -- for project splits, use `addToBalanceOf` instead of `pay`.
- `uint32 percent` -- percentage of the remaining amount (sequential, not parallel).
- `uint64 projectId` -- target project (0 = no project split).
- `address beneficiary` -- direct recipient (if no hook and no projectId).
- `IJBSplitHook hook` -- split hook contract (highest priority).
- `uint48 lockedUntil` -- timestamp until which this split is locked and cannot be modified.

**Edge cases**:
- **`splitPercent` > SPLITS_TOTAL_PERCENT**: Not validated in the hook. A `splitPercent` exceeding 1e9 would forward more than the tier's price, potentially exceeding the payment amount. However, `beforePayRecordedWith` computes the split amount from the tier price, not the payment amount, so the terminal would need to have received enough.
- **Weight adjustment**: When splits route funds away, `calculateWeight` reduces the mint weight so payers receive fewer project tokens proportional to the split fraction. This can be disabled with `issueTokensForSplits = true`.
- **Cross-currency**: Split amounts are calculated in the pricing currency, then converted to the payment token denomination. Rounding occurs at each step.
- **ERC-20 tokens**: The library pulls tokens from the terminal via `safeTransferFrom`, distributes them, and approves terminals for project splits via `forceApprove`.
