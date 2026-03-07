# nana-721-hook-v6

## Purpose

Tiered ERC-721 NFT hook for Juicebox V6 that mints NFTs when a project is paid and optionally allows NFT holders to burn them to reclaim project funds proportional to tier price.

## Contracts

| Contract | Role |
|----------|------|
| `JB721TiersHook` | Core hook: processes payments (mints NFTs), processes cash outs (burns NFTs), manages tiers, reserves, credits, metadata, and discount percents. Deployed as minimal clones. |
| `JB721TiersHookStore` | Shared singleton storage for all hook instances. Stores tiers (`JBStored721Tier`), balances, reserves, bitmaps for removed tiers, flags, and token URI resolvers. |
| `JB721TiersHookDeployer` | Factory: clones `JB721TiersHook` via `LibClone.clone` / `cloneDeterministic`, initializes, registers in address registry. |
| `JB721TiersHookProjectDeployer` | Convenience deployer: creates a Juicebox project + hook in one transaction. Wires the hook as the data hook with `useDataHookForPay: true`. |
| `JB721Hook` (abstract) | Base: implements `IJBRulesetDataHook` + `IJBPayHook` + `IJBCashOutHook`. Validates caller is a project terminal. |
| `JB721TiersHookLib` (library) | External library called via DELEGATECALL from the hook. Handles tier adjustments (`adjustTiersFor`), split amount calculation (`calculateSplitAmounts`), split fund distribution (`distributeAll`), price normalization (`normalizePaymentValue`), and token URI resolution (`resolveTokenURI`). Extracted to stay within EIP-170 contract size limit. |
| `ERC721` (abstract) | Clone-compatible ERC-721 with `_initialize(name, symbol)` instead of constructor args. |

## Key Functions

| Function | Contract | What it does |
|----------|----------|--------------|
| `initialize(projectId, name, symbol, baseUri, tokenUriResolver, contractUri, tiersConfig, flags)` | `JB721TiersHook` | One-time setup for a cloned hook instance. Stores pricing context (currency, decimals, prices contract packed into uint256), records tiers and flags in the store. |
| `afterPayRecordedWith(context)` | `JB721Hook` | Called by terminal after payment. Validates caller is a project terminal, delegates to `_processPayment`. |
| `_processPayment(context)` | `JB721TiersHook` | Normalizes payment value via pricing context, decodes payer metadata for tier IDs to mint, calls `_mintAll`, manages pay credits for overspending. |
| `afterCashOutRecordedWith(context)` | `JB721Hook` | Called by terminal during cash out. Decodes token IDs from metadata, validates ownership, burns NFTs, calls `_didBurn`. |
| `beforePayRecordedWith(context)` | `JB721Hook` | Data hook: returns original weight, calculates per-tier split amounts via `JB721TiersHookLib.calculateSplitAmounts`, and sets this contract as the pay hook with the total split amount forwarded. |
| `beforeCashOutRecordedWith(context)` | `JB721Hook` | Data hook: calculates `cashOutCount` (weight of NFTs being cashed out) and `totalSupply` (total weight of all NFTs). Rejects if fungible tokens are also being cashed out. |
| `adjustTiers(tiersToAdd, tierIdsToRemove)` | `JB721TiersHook` | Owner-only. Adds/removes tiers via the store. Requires `ADJUST_721_TIERS` permission. |
| `mintFor(tierIds, beneficiary)` | `JB721TiersHook` | Owner-only manual mint. Requires `MINT_721` permission. Passes `amount: type(uint256).max` and `isOwnerMint: true` to force the mint. |
| `mintPendingReservesFor(tierId, count)` | `JB721TiersHook` | Public. Mints pending reserve NFTs for a tier to the tier's `reserveBeneficiary`. Checks ruleset metadata for `mintPendingReservesPaused`. |
| `setMetadata(baseUri, contractUri, tokenUriResolver, encodedIPFSTUriTierId, encodedIPFSUri)` | `JB721TiersHook` | Owner-only. Updates base URI, contract URI, token URI resolver, or per-tier encoded IPFS URI. Requires `SET_721_METADATA` permission. |
| `setDiscountPercentOf(tierId, discountPercent)` | `JB721TiersHook` | Owner-only. Sets discount percent for a tier. Requires `SET_721_DISCOUNT_PERCENT` permission. |
| `deployHookFor(projectId, config, salt)` | `JB721TiersHookDeployer` | Clones the hook implementation, initializes it, transfers ownership to caller, registers in address registry. |
| `launchProjectFor(owner, deployConfig, launchConfig, controller, salt)` | `JB721TiersHookProjectDeployer` | Creates project via controller, deploys hook, wires hook as data hook with `useDataHookForPay: true`, transfers hook ownership to project. |
| `recordMint(amount, tierIds, isOwnerMint)` | `JB721TiersHookStore` | Records minting: validates supply, checks tier prices against amount (unless owner mint), generates token IDs (tierId * 1_000_000_000 + mintCount), tracks reserves. |
| `recordAddTiers(tiers)` | `JB721TiersHookStore` | Adds new tiers sorted by category. Validates against hook flags (no new reserves/votes/owner-minting if flagged). |
| `recordRemoveTierIds(tierIds)` | `JB721TiersHookStore` | Marks tiers as removed in the bitmap. Validates tier is not locked (`cannotBeRemoved`). |
| `calculateSplitAmounts(store, hook, metadataIdTarget, metadata)` | `JB721TiersHookLib` | Called in `beforePayRecordedWith`. Decodes tier IDs from payer metadata, looks up each tier's `splitPercent`, calculates `mulDiv(price, splitPercent, SPLITS_TOTAL_PERCENT)` per tier, returns `totalSplitAmount` (forwarded to hook as `amount`) and encoded `hookMetadata` (tier IDs + amounts). |
| `distributeAll(directory, projectId, hookAddress, token, encodedSplitData)` | `JB721TiersHookLib` | Called in `afterPayRecordedWith`. Decodes per-tier amounts, looks up each tier's splits from `JBSplits` by group ID (`hookAddress \| (tierId << 160)`), distributes to split recipients. Leftover goes to project balance via `addToBalance`. |
| `adjustTiersFor(store, directory, projectId, hookAddress, caller, tiersToAdd, tierIdsToRemove)` | `JB721TiersHookLib` | Called via DELEGATECALL from `adjustTiers`. Removes tiers, adds tiers, emits events, and registers any configured splits in `JBSplits` via the project's controller. |

## Integration Points

| Dependency | Import | Used For |
|------------|--------|----------|
| `@bananapus/core-v6` | `IJBDirectory`, `IJBRulesets`, `IJBPrices`, `IJBController`, `IJBTerminal`, `JBRuleset`, `JBRulesetMetadata`, `JBAfterPayRecordedContext`, `JBBeforeCashOutRecordedContext`, etc. | Terminal validation, ruleset metadata, pricing, payment/cash-out contexts |
| `@bananapus/ownable-v6` | `JBOwnable` | Project-based ownership for the hook (ownership can be transferred to a project NFT) |
| `@bananapus/permission-ids-v6` | `JBPermissionIds` | Permission IDs: `ADJUST_721_TIERS`, `MINT_721`, `SET_721_METADATA`, `SET_721_DISCOUNT_PERCENT`, `QUEUE_RULESETS`, `SET_TERMINALS` |
| `@bananapus/address-registry-v6` | `IJBAddressRegistry` | Registering deployed hook clones |
| `@openzeppelin/contracts` | `ERC2771Context`, `IERC165`, `IERC2981`, `IERC721` | Meta-transactions (trusted forwarder), interface detection, royalty standard |
| `@prb/math` | `mulDiv` | Safe fixed-point multiplication/division for price normalization |
| `solady` | `LibClone` | Minimal proxy (clone) deployment for hooks |

## Key Types

| Struct/Enum | Key Fields | Used In |
|-------------|------------|---------|
| `JB721TierConfig` | `uint104 price`, `uint32 initialSupply`, `uint32 votingUnits`, `uint16 reserveFrequency`, `address reserveBeneficiary`, `bytes32 encodedIPFSUri`, `uint24 category`, `uint8 discountPercent`, `bool allowOwnerMint`, `bool transfersPausable`, `bool cannotBeRemoved`, `bool cannotIncreaseDiscountPercent`, `uint32 splitPercent`, `JBSplit[] splits` | `adjustTiers`, `initialize`, `recordAddTiers` |
| `JB721Tier` | Same as config plus `uint32 id`, `uint32 remainingSupply`, `uint32 splitPercent`, `string resolvedUri` | Return type from `tierOf`, `tiersOf`, `tierOfTokenId` |
| `JBStored721Tier` | `uint104 price`, `uint32 remainingSupply`, `uint32 initialSupply`, `uint32 splitPercent`, `uint24 category`, `uint8 discountPercent`, `uint16 reserveFrequency`, `uint8 packedBools` | Internal storage in `JB721TiersHookStore` |
| `JB721InitTiersConfig` | `JB721TierConfig[] tiers`, `uint32 currency`, `uint8 decimals`, `IJBPrices prices` | `initialize` — defines tiers and pricing context |
| `JBDeploy721TiersHookConfig` | `string name`, `string symbol`, `string baseUri`, `IJB721TokenUriResolver tokenUriResolver`, `string contractUri`, `JB721InitTiersConfig tiersConfig`, `address reserveBeneficiary`, `JB721TiersHookFlags flags` | `deployHookFor`, `launchProjectFor` |
| `JB721TiersHookFlags` | `bool noNewTiersWithReserves`, `bool noNewTiersWithVotes`, `bool noNewTiersWithOwnerMinting`, `bool preventOverspending` | `initialize`, `recordFlags` |
| `JB721TiersRulesetMetadata` | `bool pauseTransfers`, `bool pauseMintPendingReserves` | Packed into `JBRulesetMetadata.metadata` per-ruleset |
| `JBPayDataHookRulesetConfig` | `uint48 mustStartAtOrAfter`, `uint32 duration`, `uint112 weight`, `uint32 weightCutPercent`, `IJBRulesetApprovalHook approvalHook`, `JBPayDataHookRulesetMetadata metadata`, `JBSplitGroup[] splitGroups`, `JBFundAccessLimitGroup[] fundAccessLimitGroups` | `JB721TiersHookProjectDeployer` — wraps core ruleset config with `useDataHookForPay: true` hardcoded |
| `JBPayDataHookRulesetMetadata` | Same as `JBRulesetMetadata` minus `allowSetCustomToken` (hardcoded false) and `useDataHookForPay` (hardcoded true) and `dataHook` (set to deployed hook) | `launchProjectFor`, `launchRulesetsFor`, `queueRulesetsOf` |
| `JB721TiersMintReservesConfig` | `uint32 tierId`, `uint16 count` | `mintPendingReservesFor` batch variant |
| `JB721TiersSetDiscountPercentConfig` | `uint32 tierId`, `uint16 discountPercent` | `setDiscountPercentsOf` batch variant |
| `JBBitmapWord` | `uint256 currentWord`, `uint256 currentDepth` | Internal tier removal tracking in store |

## Gotchas

- `JB721TiersHook` is deployed as a **minimal clone** (not a full deployment). The constructor sets immutables (`RULESETS`, `STORE`, `DIRECTORY`, `METADATA_ID_TARGET`), and `initialize()` sets per-instance state. Calling `initialize()` twice reverts with `JB721TiersHook_AlreadyInitialized`.
- **Pricing context is bit-packed** into a single `uint256`: currency (bits 0-31), decimals (bits 32-39), prices contract address (bits 40-199). Read it via `pricingContext()`.
- **Token IDs encode tier ID**: `tokenId = tierId * 1_000_000_000 + mintNumber`. Use `STORE.tierIdOfToken(tokenId)` to extract the tier ID.
- **Pay credits**: If a payer overpays (amount > total tier prices), the excess is stored as `payCreditsOf[beneficiary]` and can be applied to future mints. This only works when `preventOverspending` flag is `false`. Credits are only combined with payment when `payer == beneficiary`.
- **Cash outs reject fungible tokens**: `beforeCashOutRecordedWith` reverts with `JB721Hook_UnexpectedTokenCashedOut` if `context.cashOutCount > 0`. NFT cash outs and fungible token cash outs are mutually exclusive.
- **Reserve minting is permissionless** but governed by ruleset metadata. Anyone can call `mintPendingReservesFor` as long as `mintPendingReservesPaused` is not set in the current ruleset's metadata.
- `setMetadata` uses `address(this)` as the sentinel for "no change" on `tokenUriResolver` (not `address(0)`). Passing `address(0)` will clear the resolver.
- `JBPayDataHookRulesetConfig` hardcodes `allowSetCustomToken: false` and `useDataHookForPay: true` when wiring rulesets through the project deployer.
- The `_update` override in `JB721TiersHook` checks `tier.transfersPausable` and consults the current ruleset's metadata for `transfersPaused`. Transfers to `address(0)` (burns) are never blocked.
- **Tier splits** allow each tier to route a percentage of its mint price to configured recipients. `splitPercent` is out of `JBConstants.SPLITS_TOTAL_PERCENT` (1,000,000,000). When a payer mints an NFT from a tier with splits, the terminal forwards `mulDiv(price, splitPercent, SPLITS_TOTAL_PERCENT)` to the hook, which distributes it to the tier's split group. Leftover after all splits goes back to the project's balance.
- **Split group IDs** are computed as `uint256(uint160(hookAddress)) | (uint256(tierId) << 160)`. Splits are stored in the project's `JBSplits` contract (accessed via the controller) and registered automatically when tiers with `splits` are added.
- `JB721TiersHookStore` is a **shared singleton** -- all hook instances on the same chain use the same store, keyed by `address(hook)`.
- The `ERC721` abstract uses `_initialize(name, symbol)` instead of a constructor, making it clone-compatible. The standard `_owners` mapping is `internal` (not `private`).

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
            preventOverspending: false
        })
    }),
    launchProjectConfig: launchConfig,  // JBLaunchProjectConfig with rulesets, terminals, etc.
    controller: IJBController(controllerAddress),
    salt: bytes32(0)
});
```
