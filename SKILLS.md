# Juicebox 721 Hook

## Purpose

Tiered ERC-721 NFT hook for Juicebox V6 that mints NFTs when a project is paid and optionally allows NFT holders to burn them to reclaim project funds proportional to tier price.

## Contracts

| Contract | Role |
|----------|------|
| `JB721Hook` (abstract) | Abstract base hook: owns `DIRECTORY`, `METADATA_ID_TARGET`, `PROJECT_ID`. Implements `afterPayRecordedWith` (terminal validation + delegates to virtual `_processPayment`), `afterCashOutRecordedWith` (terminal validation, burn loop, delegates to virtual `_didBurn`), `beforeCashOutRecordedWith` (metadata decoding, delegates to virtual `cashOutWeightOf`/`totalCashOutWeight`), `beforePayRecordedWith` (default: forward weight), `hasMintPermissionFor` (returns false), `supportsInterface`, and `_initialize`. |
| `JB721TiersHook` | Core hook: extends `JB721Hook`. Manages tiers, reserves, credits, metadata, and discount percents. Deployed as minimal clones. Inherits `JBOwnable`, `ERC2771Context`, `JB721Hook`, `IJB721TiersHook`. Overrides `cashOutWeightOf`, `totalCashOutWeight`, `_didBurn`, `_processPayment`, and `beforePayRecordedWith` (adds tier split calculation). |
| `JB721TiersHookStore` | Shared singleton storage for all hook instances. Stores tiers (`JBStored721Tier`), balances, reserves, bitmaps for removed tiers, flags, and token URI resolvers. |
| `JB721TiersHookDeployer` | Factory: clones `JB721TiersHook` via `LibClone.clone` / `cloneDeterministic`, initializes, registers in address registry. |
| `JB721TiersHookProjectDeployer` | Convenience deployer: creates a Juicebox project + hook in one transaction. Also supports `launchRulesetsFor` and `queueRulesetsOf`. Wires the hook as the data hook with `useDataHookForPay: true`. |
| `JB721TiersHookLib` (library) | External library called via DELEGATECALL from the hook. Handles tier adjustments (`adjustTiersFor`), split amount calculation (`calculateSplitAmounts`), split fund distribution (`distributeAll`), price normalization (`normalizePaymentValue`), and token URI resolution (`resolveTokenURI`). Extracted to stay within EIP-170 contract size limit. |
| `IJB721Hook` (interface) | Interface for `JB721Hook`: extends `IJBRulesetDataHook`, `IJBPayHook`, `IJBCashOutHook`. Declares `DIRECTORY()`, `METADATA_ID_TARGET()`, `PROJECT_ID()`. |
| `ERC721` (abstract) | Clone-compatible ERC-721 with `_initialize(name, symbol)` instead of constructor args. Exposes `_setName()` and `_setSymbol()` for post-initialization updates. |

## Key Functions

| Function | Contract | What it does |
|----------|----------|--------------|
| `initialize(projectId, name, symbol, baseUri, tokenUriResolver, contractUri, tiersConfig, flags)` | `JB721TiersHook` | One-time setup for a cloned hook instance. Stores pricing context (currency, decimals, prices contract packed into uint256), records tiers and flags in the store. Registers any configured tier splits in `JBSplits` via `SPLITS.setSplitGroupsOf`. Validates `decimals <= 18`. |
| `afterPayRecordedWith(context)` | `JB721Hook` | Called by terminal after payment. Validates caller is a project terminal, delegates to virtual `_processPayment`. |
| `_processPayment(context)` | `JB721TiersHook` | Normalizes payment value via pricing context, decodes payer metadata for tier IDs to mint, calls `_mintAll`, manages pay credits for overspending. Distributes tier split funds via `JB721TiersHookLib.distributeAll` if split amounts were forwarded. |
| `afterCashOutRecordedWith(context)` | `JB721Hook` | Called by terminal during cash out. Decodes token IDs from metadata, validates ownership, burns NFTs, delegates to virtual `_didBurn`. Reverts if `msg.value != 0`. |
| `beforePayRecordedWith(context)` | `JB721TiersHook` | Data hook: calculates per-tier split amounts via `JB721TiersHookLib.calculateSplitAmounts`, adjusts the weight proportionally so the terminal only mints tokens for the amount that actually enters the project (i.e., `weight = mulDiv(context.weight, amount - totalSplitAmount, amount)`), and sets this contract as the pay hook with the total split amount forwarded. If no splits, returns original weight unchanged. If splits consume the entire payment, returns weight 0. If the `issueTokensForSplits` flag is set, returns the full `context.weight` regardless of splits. |
| `beforeCashOutRecordedWith(context)` | `JB721Hook` | Data hook: calculates `cashOutCount` (via virtual `cashOutWeightOf`) and `totalSupply` (via virtual `totalCashOutWeight`). Rejects if fungible tokens are also being cashed out. |
| `adjustTiers(tiersToAdd, tierIdsToRemove)` | `JB721TiersHook` | Owner-only. Adds/removes tiers via `JB721TiersHookLib.adjustTiersFor` (DELEGATECALL). Requires `ADJUST_721_TIERS` permission. Registers tier splits in `JBSplits` if configured. |
| `mintFor(tierIds, beneficiary)` | `JB721TiersHook` | Owner-only manual mint. Requires `MINT_721` permission. Passes `amount: type(uint256).max` and `isOwnerMint: true` to force the mint. |
| `mintPendingReservesFor(tierId, count)` | `JB721TiersHook` | Public. Mints pending reserve NFTs for a tier to the tier's `reserveBeneficiary`. Checks ruleset metadata for `mintPendingReservesPaused`. |
| `mintPendingReservesFor(configs[])` | `JB721TiersHook` | Batch variant. Calls `mintPendingReservesFor(tierId, count)` for each config. |
| `setMetadata(name, symbol, baseUri, contractUri, tokenUriResolver, encodedIPFSUriTierId, encodedIPFSUri)` | `JB721TiersHook` | Owner-only. Updates collection name, symbol, base URI, contract URI, token URI resolver, or per-tier encoded IPFS URI. Empty strings leave values unchanged. Requires `SET_721_METADATA` permission. |
| `setDiscountPercentOf(tierId, discountPercent)` | `JB721TiersHook` | Owner-only. Sets discount percent for a tier. Requires `SET_721_DISCOUNT_PERCENT` permission. |
| `setDiscountPercentsOf(configs[])` | `JB721TiersHook` | Batch variant. Sets discount percent for multiple tiers. Requires `SET_721_DISCOUNT_PERCENT` permission. |
| `tokenURI(tokenId)` | `JB721TiersHook` | Resolves token metadata URI. Delegates to `JB721TiersHookLib.resolveTokenURI`, which checks for a custom `tokenUriResolver` first, then falls back to IPFS decoding via `JBIpfsDecoder`. |
| `firstOwnerOf(tokenId)` | `JB721TiersHook` | Returns the first owner of an NFT (the address that originally received it). Stored on first transfer out; returns current owner if never transferred. |
| `pricingContext()` | `JB721TiersHook` | Unpacks and returns the currency, decimals, and prices contract from the packed `_packedPricingContext`. |
| `balanceOf(owner)` | `JB721TiersHook` | Overrides ERC-721 `balanceOf` to delegate to `STORE.balanceOf`, which sums across all tiers. |
| `hasMintPermissionFor(...)` | `JB721Hook` | Always returns `false`. Required by `IJBRulesetDataHook`; prevents the hook from granting mint permissions to anyone. |
| `supportsInterface(interfaceId)` | `JB721TiersHook` | Returns `true` for `IJB721TiersHook`, `IJBRulesetDataHook`, `IJBPayHook`, `IJBCashOutHook`, `IERC2981`, `IERC721`, `IERC721Metadata`, `IERC165`. |
| `deployHookFor(projectId, config, salt)` | `JB721TiersHookDeployer` | Clones the hook implementation, initializes it, transfers ownership to caller, registers in address registry. |
| `launchProjectFor(owner, deployConfig, launchConfig, controller, salt)` | `JB721TiersHookProjectDeployer` | Creates project via controller, deploys hook, wires hook as data hook with `useDataHookForPay: true`, transfers hook ownership to project. |
| `launchRulesetsFor(projectId, deployConfig, launchRulesetsConfig, controller, salt)` | `JB721TiersHookProjectDeployer` | Deploys a hook for an existing project and launches rulesets. Requires `QUEUE_RULESETS` and `SET_TERMINALS` permissions. Transfers hook ownership to project. |
| `queueRulesetsOf(projectId, deployConfig, queueRulesetsConfig, controller, salt)` | `JB721TiersHookProjectDeployer` | Deploys a hook and queues rulesets for an existing project. Requires `QUEUE_RULESETS` permission. Transfers hook ownership to project. |
| `recordMint(amount, tierIds, isOwnerMint)` | `JB721TiersHookStore` | Records minting: validates supply, checks tier prices against amount (unless owner mint), applies discount if set, generates token IDs (`tierId * 1_000_000_000 + mintCount`), ensures remaining supply covers pending reserves. |
| `recordAddTiers(tiers)` | `JB721TiersHookStore` | Adds new tiers sorted by category. Validates against hook flags (no new reserves/votes/owner-minting if flagged). Enforces max tier count (`type(uint16).max`), max supply per tier (`999_999_999`), discount percent bounds, non-zero supply, category sort order, and reserve+owner-mint mutual exclusion. |
| `recordRemoveTierIds(tierIds)` | `JB721TiersHookStore` | Marks tiers as removed in the bitmap. Validates tier is not locked (`cannotBeRemoved`). Does NOT update the sorted linked list -- call `cleanTiers()` afterward. |
| `recordMintReservesFor(tierId, count)` | `JB721TiersHookStore` | Mints reserve NFTs from remaining supply. Validates count does not exceed pending reserves. |
| `recordSetDiscountPercentOf(tierId, discountPercent)` | `JB721TiersHookStore` | Sets discount percent for a tier. Validates bounds (`<= DISCOUNT_DENOMINATOR`). If `cannotIncreaseDiscountPercent` is set, rejects increases. |
| `recordBurn(tokenIds)` | `JB721TiersHookStore` | Increments burn counter per tier. Trusts `msg.sender` (the hook) to have already verified ownership and burned the tokens. |
| `cleanTiers(hook)` | `JB721TiersHookStore` | Public. Removes stale entries from the sorted tier linked list after tiers have been removed via `recordRemoveTierIds`. Optimizes tier iteration. |
| `tiersOf(hook, categories, includeResolvedUri, startingId, size)` | `JB721TiersHookStore` | Returns an array of active tiers, optionally filtered by categories. Skips removed tiers. |
| `tierOf(hook, id, includeResolvedUri)` | `JB721TiersHookStore` | Returns a single tier by ID. |
| `tierOfTokenId(hook, tokenId, includeResolvedUri)` | `JB721TiersHookStore` | Returns the tier for a given token ID. |
| `totalSupplyOf(hook)` | `JB721TiersHookStore` | Returns total NFTs minted across all tiers (excluding burns). |
| `totalCashOutWeight(hook)` | `JB721TiersHookStore` | Returns total cash out weight (sum of `price * (minted + pendingReserves)` for all tiers). Uses original price, not discounted price. |
| `cashOutWeightOf(hook, tokenIds)` | `JB721TiersHookStore` | Returns combined cash out weight for specific token IDs. Uses original tier price, not discounted. |
| `votingUnitsOf(hook, account)` | `JB721TiersHookStore` | Returns total voting units for an address across all tiers. Uses custom `votingUnits` if `useVotingUnits` is set, otherwise uses tier price. |
| `tierVotingUnitsOf(hook, account, tierId)` | `JB721TiersHookStore` | Returns voting units for an address within a specific tier. |
| `calculateSplitAmounts(store, hook, metadataIdTarget, metadata)` | `JB721TiersHookLib` | Called in `beforePayRecordedWith`. Decodes tier IDs from payer metadata, looks up each tier's `splitPercent`, calculates `mulDiv(price, splitPercent, SPLITS_TOTAL_PERCENT)` per tier, returns `totalSplitAmount` and encoded `hookMetadata` (tier IDs + amounts). Amounts are in the tier pricing denomination — call `convertSplitAmounts` afterward when the payment currency differs. |
| `convertSplitAmounts(totalSplitAmount, splitMetadata, packedPricingContext, projectId, amountCurrency, amountDecimals)` | `JB721TiersHookLib` | Converts per-tier split amounts from tier pricing denomination to payment token denomination using `JBPrices.pricePerUnitOf`. Called automatically by `beforePayRecordedWith` when `totalSplitAmount != 0`. Returns early (no-op) when currencies match or no prices contract is configured. |
| `distributeAll(directory, splits, projectId, hookAddress, token, encodedSplitData)` | `JB721TiersHookLib` | Called in `afterPayRecordedWith`. Decodes per-tier amounts, looks up each tier's splits from `JBSplits` by group ID (`hookAddress | (tierId << 160)`), distributes to split recipients. Leftover goes to project balance via `addToBalance`. |
| `adjustTiersFor(store, splits, projectId, hookAddress, caller, tiersToAdd, tierIdsToRemove)` | `JB721TiersHookLib` | Called via DELEGATECALL from `adjustTiers`. Removes tiers, adds tiers, emits events, and registers any configured splits directly in `JBSplits`. |
| `normalizePaymentValue(packedPricingContext, projectId, amountValue, amountCurrency, amountDecimals)` | `JB721TiersHookLib` | Converts a payment value to the hook's pricing currency using `JBPrices`. Returns `(0, false)` if currencies differ and no prices contract is set. |
| `resolveTokenURI(store, hook, baseUri, tokenId)` | `JB721TiersHookLib` | Resolves token URI: checks for custom `tokenUriResolver` first, otherwise decodes IPFS URI via `JBIpfsDecoder`. |

## Integration Points

| Dependency | Import | Used For |
|------------|--------|----------|
| `@bananapus/core-v6` | `IJBDirectory`, `IJBRulesets`, `IJBPrices`, `IJBSplits`, `IJBTerminal`, `JBRuleset`, `JBRulesetMetadata`, `JBAfterPayRecordedContext`, `JBBeforeCashOutRecordedContext`, `JBSplit`, `JBSplitGroup`, `JBConstants`, etc. | Terminal validation, ruleset metadata, pricing, payment/cash-out contexts, splits |
| `@bananapus/ownable-v6` | `JBOwnable` | Project-based ownership for the hook (ownership can be transferred to a project NFT) |
| `@bananapus/permission-ids-v6` | `JBPermissionIds` | Permission IDs: `ADJUST_721_TIERS`, `MINT_721`, `SET_721_METADATA`, `SET_721_DISCOUNT_PERCENT`, `QUEUE_RULESETS`, `SET_TERMINALS` |
| `@bananapus/address-registry-v6` | `IJBAddressRegistry` | Registering deployed hook clones |
| `@openzeppelin/contracts` | `ERC2771Context`, `IERC165`, `IERC2981`, `IERC721`, `SafeERC20` | Meta-transactions (trusted forwarder), interface detection, royalty standard declaration, safe ERC-20 transfers for split distribution |
| `@prb/math` | `mulDiv` | Safe fixed-point multiplication/division for price normalization and discount/split calculation |
| `solady` | `LibClone` | Minimal proxy (clone) deployment for hooks |

## Key Types

| Struct/Enum | Key Fields | Used In |
|-------------|------------|---------|
| `JB721TierConfig` | `uint104 price`, `uint32 initialSupply`, `uint32 votingUnits`, `uint16 reserveFrequency`, `address reserveBeneficiary`, `bytes32 encodedIPFSUri`, `uint24 category`, `uint8 discountPercent`, `bool allowOwnerMint`, `bool useReserveBeneficiaryAsDefault`, `bool transfersPausable`, `bool useVotingUnits`, `bool cannotBeRemoved`, `bool cannotIncreaseDiscountPercent`, `uint32 splitPercent`, `JBSplit[] splits` | `adjustTiers`, `initialize`, `recordAddTiers` |
| `JB721Tier` | `uint32 id`, `uint104 price`, `uint32 remainingSupply`, `uint32 initialSupply`, `uint104 votingUnits`, `uint16 reserveFrequency`, `address reserveBeneficiary`, `bytes32 encodedIPFSUri`, `uint24 category`, `uint8 discountPercent`, `bool allowOwnerMint`, `bool transfersPausable`, `bool cannotBeRemoved`, `bool cannotIncreaseDiscountPercent`, `uint32 splitPercent`, `string resolvedUri` | Return type from `tierOf`, `tiersOf`, `tierOfTokenId` |
| `JBStored721Tier` | `uint104 price`, `uint32 remainingSupply`, `uint32 initialSupply`, `uint32 splitPercent`, `uint24 category`, `uint8 discountPercent`, `uint16 reserveFrequency`, `uint8 packedBools` (allowOwnerMint, transfersPausable, useVotingUnits, cannotBeRemoved, cannotIncreaseDiscountPercent) | Internal storage in `JB721TiersHookStore`. Voting units stored separately in `_tierVotingUnitsOf` when `useVotingUnits` is true. |
| `JB721InitTiersConfig` | `JB721TierConfig[] tiers`, `uint32 currency`, `uint8 decimals`, `IJBPrices prices` | `initialize` -- defines tiers and pricing context |
| `JBDeploy721TiersHookConfig` | `string name`, `string symbol`, `string baseUri`, `IJB721TokenUriResolver tokenUriResolver`, `string contractUri`, `JB721InitTiersConfig tiersConfig`, `address reserveBeneficiary`, `JB721TiersHookFlags flags` | `deployHookFor`, `launchProjectFor` |
| `JB721TiersHookFlags` | `bool noNewTiersWithReserves`, `bool noNewTiersWithVotes`, `bool noNewTiersWithOwnerMinting`, `bool preventOverspending`, `bool issueTokensForSplits` | `initialize`, `recordFlags` |
| `JB721TiersRulesetMetadata` | `bool pauseTransfers`, `bool pauseMintPendingReserves` | Packed into `JBRulesetMetadata.metadata` per-ruleset (bit 0 = pauseTransfers, bit 1 = pauseMintPendingReserves) |
| `JBPayDataHookRulesetConfig` | `uint48 mustStartAtOrAfter`, `uint32 duration`, `uint112 weight`, `uint32 weightCutPercent`, `IJBRulesetApprovalHook approvalHook`, `JBPayDataHookRulesetMetadata metadata`, `JBSplitGroup[] splitGroups`, `JBFundAccessLimitGroup[] fundAccessLimitGroups` | `JB721TiersHookProjectDeployer` -- wraps core ruleset config with `useDataHookForPay: true` hardcoded |
| `JBPayDataHookRulesetMetadata` | Same as `JBRulesetMetadata` minus `useDataHookForPay` (hardcoded true) and `dataHook` (set to deployed hook). | `launchProjectFor`, `launchRulesetsFor`, `queueRulesetsOf` |
| `JBLaunchProjectConfig` | `string projectUri`, `JBPayDataHookRulesetConfig[] rulesetConfigurations`, `JBTerminalConfig[] terminalConfigurations`, `string memo` | `launchProjectFor` |
| `JBLaunchRulesetsConfig` | `uint56 projectId`, `JBPayDataHookRulesetConfig[] rulesetConfigurations`, `JBTerminalConfig[] terminalConfigurations`, `string memo` | `launchRulesetsFor` |
| `JBQueueRulesetsConfig` | `uint56 projectId`, `JBPayDataHookRulesetConfig[] rulesetConfigurations`, `string memo` | `queueRulesetsOf` |
| `JB721TiersMintReservesConfig` | `uint32 tierId`, `uint16 count` | `mintPendingReservesFor` batch variant |
| `JB721TiersSetDiscountPercentConfig` | `uint32 tierId`, `uint16 discountPercent` | `setDiscountPercentsOf` batch variant |
| `JBBitmapWord` | `uint256 currentWord`, `uint256 currentDepth` | Internal tier removal tracking in store |

## Constants

| Constant | Value | Location | Meaning |
|----------|-------|----------|---------|
| `DISCOUNT_DENOMINATOR` | `200` | `JB721Constants` | Max `discountPercent` value. A `discountPercent` of 200 = 100% discount (free). A `discountPercent` of 100 = 50% off. Formula: `price -= mulDiv(price, discountPercent, 200)`. |
| `_ONE_BILLION` | `1_000_000_000` | `JB721TiersHookStore` | Used for token ID generation: `tokenId = tierId * 1_000_000_000 + tokenNumber`. Also caps max initial supply per tier at 999,999,999. |
| Max tier count | `type(uint16).max` (65,535) | `JB721TiersHookStore` | Maximum total number of tiers across all `recordAddTiers` calls for a single hook. |

## Discount Percent

Each tier has a `discountPercent` (uint8) that reduces its effective purchase price:

- The discount is applied during `recordMint`: `price -= mulDiv(price, discountPercent, DISCOUNT_DENOMINATOR)`.
- `DISCOUNT_DENOMINATOR` is 200, so `discountPercent = 100` means 50% off, `discountPercent = 200` means free.
- Discount can be changed via `setDiscountPercentOf` / `setDiscountPercentsOf` (requires `SET_721_DISCOUNT_PERCENT` permission).
- If `cannotIncreaseDiscountPercent` is set on the tier, the discount can only be decreased or kept the same -- increases are rejected by the store.
- Cash out weight always uses the **original tier price**, not the discounted price. This prevents discount changes from retroactively altering the cash-out value of already-minted NFTs.

## Voting Units

Each tier has configurable voting power:

- If `useVotingUnits` is `true` on the tier config, voting power per NFT is the custom `votingUnits` value (stored in `_tierVotingUnitsOf`).
- If `useVotingUnits` is `false`, voting power per NFT defaults to the tier's `price`.
- The `noNewTiersWithVotes` flag blocks adding new tiers with any voting power -- this means blocking tiers where `(useVotingUnits && votingUnits != 0)` OR `(!useVotingUnits && price != 0)`.
- Total voting units for an address are computed by `votingUnitsOf(hook, account)`, which sums `balance * votingPower` across all tiers.

## Reserve Minting

- Reserves accumulate as NFTs are purchased: for every `reserveFrequency` non-reserve mints, one reserve NFT becomes available.
- Pending count: `ceil(numberOfNonReserveMints / reserveFrequency) - numberOfReservesMintedFor`.
- Reserves are minted to the tier's `reserveBeneficiary` (or the hook's `defaultReserveBeneficiaryOf` as fallback).
- Reserve minting is permissionless (`mintPendingReservesFor`), but can be paused per-ruleset via `pauseMintPendingReserves` in `JB721TiersRulesetMetadata`.
- Supply is protected: `recordMint` ensures remaining supply covers pending reserves after each purchase.
- Tiers with `allowOwnerMint: true` cannot have a `reserveFrequency` -- the store rejects this combination.

## Tier Splits

- Each tier can route a percentage of its mint price to configured split recipients. The `splitPercent` field (out of `JBConstants.SPLITS_TOTAL_PERCENT` = 1,000,000,000) determines how much of the price is forwarded.
- Split recipients are stored in `JBSplits` using group IDs computed as `uint256(uint160(hookAddress)) | (uint256(tierId) << 160)`.
- Splits are registered in `JBSplits` both during `initialize()` (for tiers included at launch) and during `adjustTiers()` (for tiers added later), using the hook's `SPLITS` immutable directly.
- In `beforePayRecordedWith`, `calculateSplitAmounts` decodes tier IDs from payer metadata, computes `mulDiv(price, splitPercent, SPLITS_TOTAL_PERCENT)` per tier, and returns the total to be forwarded to the hook. If the payment currency differs from the tier pricing currency, `convertSplitAmounts` converts the amounts to the payment token denomination using the configured `JBPrices` contract. The weight is adjusted down proportionally unless the `issueTokensForSplits` flag is set, in which case the full `context.weight` is returned.
- In `afterPayRecordedWith`, `distributeAll` distributes forwarded funds to each tier's split group recipients. Leftover after all splits goes back to the project's balance via `addToBalance`.
- Split recipients can be projects (via `terminal.pay` or `terminal.addToBalance`) or plain addresses (direct ETH transfer or `SafeERC20.safeTransfer`). Splits with no `projectId` and no `beneficiary` are skipped -- their share stays in the leftover and is routed to the project's own balance via `addToBalanceOf`, preventing a misconfigured split from bricking the payout distribution.

## Gotchas

- `JB721TiersHook` is deployed as a **minimal clone** (not a full deployment). The constructor sets immutables (`RULESETS`, `STORE`, `SPLITS`, `DIRECTORY`, `METADATA_ID_TARGET`), and `initialize()` sets per-instance state. Calling `initialize()` twice reverts with `JB721TiersHook_AlreadyInitialized`.
- **`JB721Hook` abstract base**: `JB721TiersHook` extends `JB721Hook`, which handles generic 721 hook lifecycle (terminal validation, burn loop, metadata decoding). `JB721TiersHook` overrides `cashOutWeightOf`, `totalCashOutWeight`, `_didBurn`, `_processPayment`, and `beforePayRecordedWith`. Errors like `JB721Hook_InvalidPay` and `JB721Hook_InvalidCashOut` are defined on the abstract class, not `JB721TiersHook`.
- **Pricing context is bit-packed** into a single `uint256`: currency (bits 0-31), decimals (bits 32-39), prices contract address (bits 40-199). Read it via `pricingContext()`.
- **Pricing decimals must be <= 18**: `initialize` reverts with `JB721TiersHook_InvalidPricingDecimals` otherwise.
- **Token IDs encode tier ID**: `tokenId = tierId * 1_000_000_000 + mintNumber`. Use `STORE.tierIdOfToken(tokenId)` to extract the tier ID.
- **Pay credits**: If a payer overpays (amount > total tier prices), the excess is stored as `payCreditsOf[beneficiary]` and can be applied to future mints. This only works when `preventOverspending` flag is `false`. Credits are only combined with payment when `payer == beneficiary`.
- **Cash outs reject fungible tokens**: `beforeCashOutRecordedWith` reverts with `JB721TiersHook_UnexpectedTokenCashedOut` if `context.cashOutCount > 0`. NFT cash outs and fungible token cash outs are mutually exclusive.
- **Cash out weight uses original price**: `cashOutWeightOf` and `totalCashOutWeight` use the full tier `price`, not the discounted price. This prevents discount changes from altering the cash-out value of already-minted NFTs.
- **Pending reserves inflate totalCashOutWeight**: `totalCashOutWeight` includes pending reserves in the denominator (`price * (minted + pendingReserves)`). This dilutes cash-out value before reserves are minted, preventing early cashers from extracting more than their fair share.
- **Reserve minting is permissionless** but governed by ruleset metadata. Anyone can call `mintPendingReservesFor` as long as `mintPendingReservesPaused` is not set in the current ruleset's metadata.
- **Reserve + owner-mint mutual exclusion**: Tiers with `allowOwnerMint: true` cannot have a `reserveFrequency`. The store rejects this combination during `recordAddTiers`.
- `setMetadata` accepts `name` and `symbol` as the first two parameters. Empty strings leave the current values unchanged.
- `setMetadata` uses `address(this)` as the sentinel for "no change" on `tokenUriResolver` (not `address(0)`). Passing `address(0)` will clear the resolver.
- `JBPayDataHookRulesetConfig` hardcodes `useDataHookForPay: true` when wiring rulesets through the project deployer. All other metadata fields are passed through.
- The `_update` override in `JB721TiersHook` checks `tier.transfersPausable` and consults the current ruleset's metadata for `transfersPaused`. Transfers to `address(0)` (burns) are never blocked.
- **IERC2981 declared but not implemented**: `supportsInterface` returns `true` for `IERC2981`, but no `royaltyInfo` function is implemented. Callers querying `royaltyInfo` will get a revert. This appears intentional -- the interface is declared for future extension or to signal capability to marketplaces that may override behavior.
- **Tier splits**: Each tier can route a percentage of its mint price to configured split recipients. `splitPercent` is out of `JBConstants.SPLITS_TOTAL_PERCENT` (1,000,000,000). Split group IDs are `uint256(uint160(hookAddress)) | (uint256(tierId) << 160)`.
- **`useReserveBeneficiaryAsDefault` overwrites globally**: Adding a tier with `useReserveBeneficiaryAsDefault: true` silently overwrites `defaultReserveBeneficiaryOf` for ALL existing tiers that lack a tier-specific beneficiary. A `SetDefaultReserveBeneficiary` event is emitted when the default changes.
- **Removing tiers does not update the sorted list**: `recordRemoveTierIds` only marks tiers in the bitmap. Call `cleanTiers()` afterward to remove them from the iteration sequence.
- `JB721TiersHookStore` is a **shared singleton** -- all hook instances on the same chain use the same store, keyed by `address(hook)`.
- The `ERC721` abstract uses `_initialize(name, symbol)` instead of a constructor, making it clone-compatible. It also exposes `_setName()` and `_setSymbol()` for post-initialization updates. The standard `_owners` mapping is `internal` (not `private`).
- **`hasMintPermissionFor` always returns `false`**: The hook never grants mint permission to any address. This is part of the `IJBRulesetDataHook` interface.
- **Max tier count is 65,535** (`type(uint16).max`). Adding tiers beyond this limit reverts.
- **Max initial supply per tier is 999,999,999** (`_ONE_BILLION - 1`). Exceeding this would cause token ID overflow into the next tier's ID space.
- **`noNewTiersWithVotes` blocks all voting power**: It rejects tiers where voting units would be non-zero, whether from custom `votingUnits` or from a non-zero `price` (when `useVotingUnits` is false).
- **`firstOwnerOf` is lazy**: The first owner is only stored when the token is first transferred away from its original holder. Before any transfer, `firstOwnerOf` returns the current owner.
- **Tiers must be sorted by category, NOT price.** `recordAddTiers` reverts with `JB721TiersHookStore_InvalidCategorySortOrder` if tiers aren't in ascending category order. The `JB721InitTiersConfig` struct comment previously said "sorted by price" but the code enforces category ordering. Within the same category, tiers can be in any order.
- **Always use `JB721TiersHookProjectDeployer.launchProjectFor` even without NFTs.** Pass an empty tiers array to enable future NFT additions without migration. If a project is launched via `JBController.launchProjectFor` instead, adding NFT tiers later requires wiring a new data hook into a new ruleset — using the 721 deployer from the start avoids this.

## Example Integration

```solidity
import {IJB721TiersHookProjectDeployer} from "@bananapus/721-hook-v6/src/interfaces/IJB721TiersHookProjectDeployer.sol";
import {JBDeploy721TiersHookConfig} from "@bananapus/721-hook-v6/src/structs/JBDeploy721TiersHookConfig.sol";
import {JB721TierConfig} from "@bananapus/721-hook-v6/src/structs/JB721TierConfig.sol";
import {JB721InitTiersConfig} from "@bananapus/721-hook-v6/src/structs/JB721InitTiersConfig.sol";
import {JB721TiersHookFlags} from "@bananapus/721-hook-v6/src/structs/JB721TiersHookFlags.sol";
import {JBLaunchProjectConfig} from "@bananapus/721-hook-v6/src/structs/JBLaunchProjectConfig.sol";
import {JBPayDataHookRulesetConfig} from "@bananapus/721-hook-v6/src/structs/JBPayDataHookRulesetConfig.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";

// Build a single tier: 0.1 ETH, supply of 100, with IPFS artwork.
JB721TierConfig[] memory tiers = new JB721TierConfig[](1);
tiers[0] = JB721TierConfig({
    price: 0.1 ether,
    initialSupply: 100,
    votingUnits: 0,
    reserveFrequency: 0,
    reserveBeneficiary: address(0),
    encodedIPFSUri: 0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89, // example CID
    category: 1,
    discountPercent: 0,
    allowOwnerMint: false,
    useReserveBeneficiaryAsDefault: false,
    transfersPausable: false,
    useVotingUnits: false,
    cannotBeRemoved: false,
    cannotIncreaseDiscountPercent: false,
    splitPercent: 0,
    splits: new JBSplit[](0)
});

// Deploy a project with the 721 hook attached.
(uint256 projectId, IJB721TiersHook hook) = projectDeployer.launchProjectFor({
    owner: msg.sender,
    deployTiersHookConfig: JBDeploy721TiersHookConfig({
        name: "My NFT Collection",
        symbol: "MNFT",
        baseUri: "ipfs://",
        tokenUriResolver: IJB721TokenUriResolver(address(0)),
        contractUri: "",
        tiersConfig: JB721InitTiersConfig({
            tiers: tiers,
            currency: 1,        // ETH
            decimals: 18,
            prices: IJBPrices(address(0))  // no cross-currency pricing
        }),
        reserveBeneficiary: address(0),
        flags: JB721TiersHookFlags({
            noNewTiersWithReserves: false,
            noNewTiersWithVotes: false,
            noNewTiersWithOwnerMinting: false,
            preventOverspending: false,
            issueTokensForSplits: false
        })
    }),
    launchProjectConfig: launchConfig,  // JBLaunchProjectConfig with rulesets, terminals, etc.
    controller: IJBController(controllerAddress),
    salt: bytes32(0)
});
```
