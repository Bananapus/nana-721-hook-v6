// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core-v6/src/structs/JBBeforePayRecordedContext.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

import {IJB721TiersHookStore} from "../interfaces/IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "../interfaces/IJB721TokenUriResolver.sol";

import {JB721Constants} from "./JB721Constants.sol";
import {JBIpfsDecoder} from "./JBIpfsDecoder.sol";

import {JB721TierConfig} from "../structs/JB721TierConfig.sol";

/// @notice External library for JB721TiersHook operations extracted to stay within the EIP-170 contract size limit.
/// @dev Handles tier adjustments, split calculations, price normalization, and split fund distribution.
library JB721TiersHookLib {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JB721TiersHook_CantBuyWithCredits(uint256 restrictedCost, uint256 freshValue);
    error JB721TiersHook_Overspending(uint256 leftoverAmount);
    error JB721TiersHookLib_NoTerminalForLeftover(uint256 projectId, address token, uint256 leftoverAmount);
    error JB721TiersHookLib_SplitFallbackFailed(uint256 projectId, address token, uint256 amount, bytes reason);
    error JB721TiersHookLib_TokenTransferAmountMismatch(uint256 expectedAmount, uint256 receivedAmount);

    //*********************************************************************//
    // ------------------------------- events ---------------------------- //
    //*********************************************************************//

    event AddTier(uint256 indexed tierId, JB721TierConfig tier, address caller);
    event RemoveTier(uint256 indexed tierId, address caller);
    event SetDiscountPercent(uint256 indexed tierId, uint256 discountPercent, address caller);
    event SplitPayoutReverted(uint256 indexed projectId, JBSplit split, uint256 amount, bytes reason, address caller);

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Handles the full tier adjustment logic: removes tiers, adds tiers, emits events, and sets splits.
    /// @dev Called via DELEGATECALL from the hook, so events are emitted from the hook's address.
    /// @param store The 721 tiers hook store.
    /// @param splits The splits contract to register tier split groups in.
    /// @param projectId The project ID.
    /// @param hookAddress The hook address.
    /// @param caller The msg.sender of the original call (for event emission).
    /// @param tiersToAdd The tier configs to add.
    /// @param tierIdsToRemove The tier IDs to remove.
    function adjustTiersFor(
        IJB721TiersHookStore store,
        IJBSplits splits,
        uint256 projectId,
        address hookAddress,
        address caller,
        JB721TierConfig[] calldata tiersToAdd,
        uint256[] calldata tierIdsToRemove
    )
        external
    {
        // Remove tiers.
        if (tierIdsToRemove.length != 0) {
            for (uint256 i; i < tierIdsToRemove.length;) {
                emit RemoveTier({tierId: tierIdsToRemove[i], caller: caller});

                unchecked {
                    ++i;
                }
            }
            store.recordRemoveTierIds(tierIdsToRemove);
        }

        // Add tiers.
        if (tiersToAdd.length != 0) {
            uint256[] memory tierIdsAdded = store.recordAddTiers(tiersToAdd);

            for (uint256 i; i < tiersToAdd.length;) {
                emit AddTier({tierId: tierIdsAdded[i], tier: tiersToAdd[i], caller: caller});

                unchecked {
                    ++i;
                }
            }

            // Set split groups for tiers that have splits configured.
            _setSplitGroupsFor({
                splits: splits,
                projectId: projectId,
                hookAddress: hookAddress,
                tiersToAdd: tiersToAdd,
                tierIdsAdded: tierIdsAdded
            });
        }
    }

    /// @notice Pulls ERC-20 tokens from the terminal (if needed) and distributes forwarded funds to tier splits.
    /// @dev For ERC-20 tokens, pulls from the terminal using the allowance it granted via _beforeTransferTo.
    /// @param directory The directory to look up terminals.
    /// @param splits The splits contract to read tier split groups from.
    /// @param projectId The project ID of the hook.
    /// @param hookAddress The hook address (for computing split group IDs).
    /// @param token The token to distribute.
    /// @param amount The total amount to distribute.
    /// @param decimals The token decimals.
    /// @param encodedSplitData The encoded per-tier breakdown from hookMetadata.
    function distributeAll(
        IJBDirectory directory,
        IJBSplits splits,
        uint256 projectId,
        address hookAddress,
        address token,
        uint256 amount,
        uint256 decimals,
        bytes calldata encodedSplitData
    )
        external
    {
        // For ERC20 tokens, pull from terminal using the allowance it granted via _beforeTransferTo.
        if (token != JBConstants.NATIVE_TOKEN) {
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            SafeERC20.safeTransferFrom({token: IERC20(token), from: msg.sender, to: address(this), value: amount});
            uint256 receivedAmount = IERC20(token).balanceOf(address(this)) - balanceBefore;
            if (receivedAmount != amount) {
                revert JB721TiersHookLib_TokenTransferAmountMismatch({
                    expectedAmount: amount, receivedAmount: receivedAmount
                });
            }
        }

        (uint16[] memory tierIds, uint256[] memory amounts) = abi.decode(encodedSplitData, (uint16[], uint256[]));

        for (uint256 i; i < tierIds.length;) {
            if (amounts[i] == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            uint256 groupId = uint256(uint160(hookAddress)) | (uint256(tierIds[i]) << 160);
            _distributeSingleSplit({
                directory: directory,
                splitsContract: splits,
                projectId: projectId,
                token: token,
                groupId: groupId,
                amount: amounts[i],
                decimals: decimals
            });

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Prepares NFT minting data for a payment: combines credits, decodes metadata, records mint, and checks
    /// overspending.
    /// @dev Called via DELEGATECALL from the hook; uses address(this) as the hook address.
    /// Reverts with JB721TiersHook_CantBuyWithCredits or JB721TiersHook_Overspending on failure.
    /// @param store The 721 tiers hook store.
    /// @param metadataIdTarget The metadata ID target for resolving pay metadata.
    /// @param value The normalized payment value.
    /// @param payer The address that initiated the payment.
    /// @param beneficiary The address to mint NFTs to and track credits for.
    /// @param payCredits The beneficiary's current pay credits balance.
    /// @param payerMetadata The metadata provided by the payer.
    /// @return tokenIds The token IDs minted (empty if none).
    /// @return tierIdsToMint The tier IDs corresponding to each minted token (empty if none).
    /// @return newPayCredits The beneficiary's updated pay credits balance.
    function prepareMint(
        IJB721TiersHookStore store,
        address metadataIdTarget,
        uint256 value,
        address payer,
        address beneficiary,
        uint256 payCredits,
        bytes calldata payerMetadata
    )
        external
        returns (uint256[] memory tokenIds, uint16[] memory tierIdsToMint, uint256 newPayCredits)
    {
        // Resolve metadata first (minimal stack: only 3 return vars). Scope block frees temporaries.
        bool payerDisallowsOverspending;
        {
            (bool found, bytes memory metadata) = JBMetadataResolver.getDataFor({
                id: JBMetadataResolver.getId({purpose: "pay", target: metadataIdTarget}), metadata: payerMetadata
            });

            if (found) {
                bool payerAllowsOverspending;
                (payerAllowsOverspending, tierIdsToMint) = abi.decode(metadata, (bool, uint16[]));
                payerDisallowsOverspending = !payerAllowsOverspending;
            }
        }

        // Set the leftover amount as the initial value.
        uint256 leftoverAmount = value;

        // If the payer is the effective beneficiary, combine their NFT credits with the amount paid.
        // Reuse newPayCredits to hold unused credits (avoids an extra local variable).
        if (payer == beneficiary) {
            leftoverAmount += payCredits;
        } else {
            newPayCredits = payCredits;
        }

        // Determine whether overspending is allowed (collection flag AND payer preference).
        bool allowOverspending = !store.flagsOf(address(this)).preventOverspending && !payerDisallowsOverspending;

        // Record the mints.
        if (tierIdsToMint.length != 0) {
            uint256 restrictedCost;

            (tokenIds, leftoverAmount, restrictedCost) =
                store.recordMint({amount: leftoverAmount, tierIds: tierIdsToMint, isOwnerMint: false});

            // Credit-restricted tiers must be fully covered by fresh payment (not stored credits).
            if (restrictedCost > value) {
                revert JB721TiersHook_CantBuyWithCredits({restrictedCost: restrictedCost, freshValue: value});
            }
        }

        // If overspending isn't allowed, revert.
        if (leftoverAmount != 0 && !allowOverspending) {
            revert JB721TiersHook_Overspending({leftoverAmount: leftoverAmount});
        }

        // Compute the new pay credits balance: leftover + unused credits (held in newPayCredits).
        newPayCredits = leftoverAmount + newPayCredits;
    }

    /// @notice Records new tiers, emits events, and sets their split groups.
    /// @dev Used during initialization when tier configs are in memory.
    /// @param store The 721 tiers hook store.
    /// @param splits The splits contract to register tier split groups in.
    /// @param projectId The project ID.
    /// @param hookAddress The hook address.
    /// @param caller The msg.sender of the original call (for event emission).
    /// @param tiersToAdd The tier configs to add.
    function recordAddTiersFor(
        IJB721TiersHookStore store,
        IJBSplits splits,
        uint256 projectId,
        address hookAddress,
        address caller,
        JB721TierConfig[] memory tiersToAdd
    )
        external
    {
        uint256[] memory tierIdsAdded = store.recordAddTiers(tiersToAdd);

        for (uint256 i; i < tiersToAdd.length;) {
            emit AddTier({tierId: tierIdsAdded[i], tier: tiersToAdd[i], caller: caller});

            unchecked {
                ++i;
            }
        }

        // Set split groups for tiers that have splits configured.
        _setSplitGroupsFor({
            splits: splits,
            projectId: projectId,
            hookAddress: hookAddress,
            tiersToAdd: tiersToAdd,
            tierIdsAdded: tierIdsAdded
        });
    }

    /// @notice Set the discount percent for a tier, emitting an event and recording it in the store.
    /// @param store The 721 tiers hook store.
    /// @param tierId The ID of the tier.
    /// @param discountPercent The discount percent to set.
    /// @param caller The msg.sender of the original call.
    function setDiscountPercentOf(
        IJB721TiersHookStore store,
        uint256 tierId,
        uint256 discountPercent,
        address caller
    )
        external
    {
        emit SetDiscountPercent({tierId: tierId, discountPercent: discountPercent, caller: caller});
        store.recordSetDiscountPercentOf({tierId: tierId, discountPercent: discountPercent});
    }

    //*********************************************************************//
    // ----------------------- external views ---------------------------- //
    //*********************************************************************//

    /// @notice Computes split amounts, weight adjustment, and resolved beneficiary for a payment.
    /// @dev Called via DELEGATECALL from the hook; uses address(this) as the hook address.
    /// @param store The 721 tiers hook store.
    /// @param metadataIdTarget The metadata ID target for resolving pay metadata.
    /// @param packedPricingContext The packed pricing context (currency, decimals).
    /// @param prices The prices contract used for currency conversion.
    /// @param context The full payment context.
    /// @return weight The adjusted weight for token minting.
    /// @return totalSplitAmount The total amount to forward for splits.
    /// @return splitMetadata Encoded per-tier breakdown (tierIds, amounts).
    /// @return beneficiary The resolved beneficiary address.
    /// @return splitCreditWeight The weight attributable to tier splits when `issueTokensForSplits` is true.
    /// Zero when splits are absent or `issueTokensForSplits` is false.
    function computeSplitsAndWeight(
        IJB721TiersHookStore store,
        address metadataIdTarget,
        uint256 packedPricingContext,
        IJBPrices prices,
        JBBeforePayRecordedContext calldata context
    )
        external
        view
        returns (
            uint256 weight,
            uint256 totalSplitAmount,
            bytes memory splitMetadata,
            address beneficiary,
            uint256 splitCreditWeight
        )
    {
        // Calculate per-tier split amounts.
        (totalSplitAmount, splitMetadata) = _calculateSplitAmounts({
            store: store, hook: address(this), metadataIdTarget: metadataIdTarget, metadata: context.metadata
        });

        // Convert split amounts from tier pricing to payment token denomination (if currencies differ)
        // and cap at the actual payment value so the terminal never forwards more than was paid.
        if (totalSplitAmount != 0) {
            (totalSplitAmount, splitMetadata) = _convertAndCapSplitAmounts({
                totalSplitAmount: totalSplitAmount,
                splitMetadata: splitMetadata,
                packedPricingContext: packedPricingContext,
                prices: prices,
                context: context
            });
        }

        // Adjust weight so the terminal mints tokens only for the amount that actually enters the project.
        weight = _calculateWeight({
            contextWeight: context.weight,
            amountValue: context.amount.value,
            totalSplitAmount: totalSplitAmount,
            store: store,
            hook: address(this)
        });

        // When issueTokensForSplits is true and there are splits, compute the weight portion
        // attributable to tier splits. Downstream compositors (e.g. JBOmnichainDeployer) use this
        // to preserve split credit when an extra hook (buyback) returns weight=0.
        if (totalSplitAmount != 0 && context.amount.value != 0 && store.flagsOf(address(this)).issueTokensForSplits) {
            splitCreditWeight = mulDiv(context.weight, totalSplitAmount, context.amount.value);
        }

        // Resolve the effective beneficiary from payment metadata.
        beneficiary = context.beneficiary;
        {
            (bool found, bytes memory data) =
                JBMetadataResolver.getDataFor({id: JB721Constants.BENEFICIARY_METADATA_ID, metadata: context.metadata});
            if (found && data.length >= 32) {
                address metadataBeneficiary = abi.decode(data, (address));
                if (metadataBeneficiary != address(0)) beneficiary = metadataBeneficiary;
            }
        }
    }

    /// @notice Normalizes a payment value based on the packed pricing context.
    /// @param packedPricingContext The packed pricing context (currency, decimals).
    /// @param prices The prices contract used for currency conversion.
    /// @param projectId The project ID.
    /// @param amountValue The payment amount value.
    /// @param amountCurrency The payment amount currency.
    /// @param amountDecimals The payment amount decimals.
    /// @return value The normalized value.
    /// @return valid Whether the value is valid (false means no prices contract and currencies differ).
    function normalizePaymentValue(
        uint256 packedPricingContext,
        IJBPrices prices,
        uint256 projectId,
        uint256 amountValue,
        uint256 amountCurrency,
        uint256 amountDecimals
    )
        external
        view
        returns (uint256 value, bool valid)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 pricingCurrency = uint256(uint32(packedPricingContext));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 pricingDecimals = uint256(uint8(packedPricingContext >> 32));
        if (amountCurrency == pricingCurrency) {
            if (amountDecimals == pricingDecimals) return (amountValue, true);
            if (amountDecimals > pricingDecimals) {
                return (amountValue / (10 ** (amountDecimals - pricingDecimals)), true);
            }
            return (amountValue * (10 ** (pricingDecimals - amountDecimals)), true);
        }

        if (address(prices) == address(0)) return (0, false);

        value = mulDiv({
            x: amountValue,
            y: 10 ** pricingDecimals,
            denominator: prices.pricePerUnitOf({
                projectId: projectId,
                pricingCurrency: amountCurrency,
                unitCurrency: pricingCurrency,
                decimals: amountDecimals
            })
        });
        valid = true;
    }

    /// @notice Resolves the token URI for a given NFT token ID.
    /// @dev Extracted to the library to keep JBIpfsDecoder bytecode out of the hook contract (EIP-170 compliance).
    /// @param store The 721 tiers hook store.
    /// @param hook The hook address.
    /// @param baseUri The base URI for IPFS-based token URIs.
    /// @param tokenId The token ID to resolve the URI for.
    /// @return The resolved token URI string.
    function resolveTokenURI(
        IJB721TiersHookStore store,
        address hook,
        string memory baseUri,
        uint256 tokenId
    )
        external
        view
        returns (string memory)
    {
        // Get a reference to the `tokenUriResolver`.
        IJB721TokenUriResolver resolver = store.tokenUriResolverOf(hook);

        // If a `tokenUriResolver` is set, use it to resolve the token URI.
        if (address(resolver) != address(0)) return resolver.tokenUriOf({nft: hook, tokenId: tokenId});

        // Otherwise, return the token URI corresponding with the NFT's tier.
        return
            JBIpfsDecoder.decode({
                baseUri: baseUri, hexString: store.encodedTierIPFSUriOf({hook: hook, tokenId: tokenId})
            });
    }

    //*********************************************************************//
    // ----------------------- internal views ---------------------------- //
    //*********************************************************************//

    /// @notice Calculates per-tier split amounts for a pay event.
    /// @param store The 721 tiers hook store.
    /// @param hook The hook address.
    /// @param metadataIdTarget The metadata ID target for resolving pay metadata.
    /// @param metadata The payer metadata.
    /// @return totalSplitAmount The total amount to forward for splits.
    /// @return hookMetadata Encoded per-tier breakdown (tierIds, amounts) for afterPay.
    function _calculateSplitAmounts(
        IJB721TiersHookStore store,
        address hook,
        address metadataIdTarget,
        bytes calldata metadata
    )
        internal
        view
        returns (uint256 totalSplitAmount, bytes memory hookMetadata)
    {
        // Decode tier IDs from metadata within a scope to free stack slots for the loop below.
        uint16[] memory tierIdsToMint;
        {
            (bool found, bytes memory data) = JBMetadataResolver.getDataFor({
                id: JBMetadataResolver.getId({purpose: "pay", target: metadataIdTarget}), metadata: metadata
            });
            if (!found) return (0, bytes(""));
            (, tierIdsToMint) = abi.decode(data, (bool, uint16[]));
        }
        if (tierIdsToMint.length == 0) return (0, bytes(""));

        uint16[] memory splitTierIds = new uint16[](tierIdsToMint.length);
        uint256[] memory splitAmounts = new uint256[](tierIdsToMint.length);
        uint256 splitTierCount;

        for (uint256 i; i < tierIdsToMint.length;) {
            // Get only the pricing fields (lightweight — avoids full struct construction).
            (uint104 tierPrice, uint32 tierSplitPercent, uint8 tierDiscountPercent) =
                store.tierPricingOf({hook: hook, id: tierIdsToMint[i]});
            if (tierSplitPercent != 0) {
                // Apply discount to tier price to match the discounted price that recordMint charges.
                // Note on discount semantics: `discountPercent` uses a denominator of 200 (JB721Constants
                // .DISCOUNT_DENOMINATOR), so a value of 200 represents a 100% discount (free mint). Even with a
                // 100% discount, the ORIGINAL tier price (`tier.price`) is used for the cashout weight calculation
                // in `cashOutWeightOf`. This means free/discounted mints still carry their full cashout weight
                // value. Project owners should be aware that discounted mints dilute the cashout pool at full
                // weight while contributing less (or no) payment to the treasury.
                uint256 effectivePrice = tierPrice;
                if (tierDiscountPercent > 0) {
                    effectivePrice -= mulDiv({
                        x: effectivePrice, y: tierDiscountPercent, denominator: JB721Constants.DISCOUNT_DENOMINATOR
                    });
                }
                splitTierIds[splitTierCount] = tierIdsToMint[i];
                splitAmounts[splitTierCount] =
                    mulDiv({x: effectivePrice, y: tierSplitPercent, denominator: JBConstants.SPLITS_TOTAL_PERCENT});
                totalSplitAmount += splitAmounts[splitTierCount];
                splitTierCount++;
            }

            unchecked {
                ++i;
            }
        }

        if (splitTierCount != 0) {
            assembly ("memory-safe") {
                mstore(splitTierIds, splitTierCount)
                mstore(splitAmounts, splitTierCount)
            }
            hookMetadata = abi.encode(splitTierIds, splitAmounts);
        }
    }

    /// @notice Calculates the weight for token minting after accounting for tier split amounts.
    /// @dev Extracted from the hook to keep mulDiv's bytecode out of the hook (EIP-170 compliance).
    /// @param contextWeight The original weight from the payment context.
    /// @param amountValue The payment amount value.
    /// @param totalSplitAmount The total amount routed to tier splits.
    /// @param store The 721 tiers hook store (to read flags).
    /// @param hook The hook address.
    /// @return weight The adjusted weight for token minting.
    function _calculateWeight(
        uint256 contextWeight,
        uint256 amountValue,
        uint256 totalSplitAmount,
        IJB721TiersHookStore store,
        address hook
    )
        internal
        view
        returns (uint256 weight)
    {
        if (totalSplitAmount == 0 || store.flagsOf(hook).issueTokensForSplits) {
            // No splits, or hook configured to give full token credit regardless — full weight.
            weight = contextWeight;
        } else if (amountValue > totalSplitAmount) {
            // Partial splits — scale weight by the fraction that enters the project.
            weight = mulDiv({x: contextWeight, y: amountValue - totalSplitAmount, denominator: amountValue});
        } else {
            // Splits consume the entire payment — no tokens should be minted.
            weight = 0;
        }
    }

    /// @notice Converts split amounts from tier pricing to payment denomination (if currencies differ), then caps
    /// the total at the actual payment value — proportionally reducing per-tier amounts when the cap applies.
    /// @dev Combines currency conversion and cap into one call to keep hook bytecode under EIP-170.
    /// @param totalSplitAmount The total split amount in tier pricing denomination.
    /// @param splitMetadata The encoded per-tier breakdown (tierIds, amounts).
    /// @param packedPricingContext The packed pricing context (currency in bits 0-31, decimals in bits 32-39).
    /// @param prices The prices contract used for currency conversion.
    /// @param context The full payment context (provides projectId, amount currency/decimals/value).
    /// @return convertedTotal The total split amount after conversion and capping.
    /// @return convertedMetadata The re-encoded per-tier breakdown with adjusted amounts.
    function _convertAndCapSplitAmounts(
        uint256 totalSplitAmount,
        bytes memory splitMetadata,
        uint256 packedPricingContext,
        IJBPrices prices,
        JBBeforePayRecordedContext calldata context
    )
        internal
        view
        returns (uint256 convertedTotal, bytes memory convertedMetadata)
    {
        // Start from the input values; conversion and capping modify them in-place below.
        convertedTotal = totalSplitAmount;
        convertedMetadata = splitMetadata;

        // Extract pricing decimals for reuse below.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 pricingDecimals = uint256(uint8(packedPricingContext >> 32));

        // Convert each per-tier amount from the tier pricing currency to the payment currency.
        // forge-lint: disable-next-line(unsafe-typecast)
        if (context.amount.currency != uint256(uint32(packedPricingContext))) {
            // No price oracle available — return 0 to skip the split rather than forwarding an unconverted
            // amount denominated in the wrong currency, which would over- or under-pay.
            if (address(prices) == address(0)) return (0, convertedMetadata);

            {
                // Get the price ratio: how many payment-currency units per one tier-pricing-currency unit.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 ratio = prices.pricePerUnitOf({
                    projectId: context.projectId,
                    pricingCurrency: context.amount.currency,
                    // forge-lint: disable-next-line(unsafe-typecast)
                    unitCurrency: uint256(uint32(packedPricingContext)),
                    decimals: context.amount.decimals
                });

                // The denominator scales each amount from tier-pricing decimals to payment-token decimals.
                uint256 denom = 10 ** pricingDecimals;

                // Decode per-tier breakdown so each amount can be converted individually.
                (uint16[] memory tierIds, uint256[] memory amounts) =
                    abi.decode(convertedMetadata, (uint16[], uint256[]));

                // Re-accumulate the total from converted amounts to avoid rounding drift.
                convertedTotal = 0;
                for (uint256 i; i < amounts.length;) {
                    // Convert this tier's amount: amount * ratio / 10^pricingDecimals.
                    amounts[i] = mulDiv({x: amounts[i], y: ratio, denominator: denom});
                    convertedTotal += amounts[i];

                    unchecked {
                        ++i;
                    }
                }

                // Re-encode with the converted amounts.
                convertedMetadata = abi.encode(tierIds, amounts);
            }
        } else if (context.amount.decimals != pricingDecimals) {
            // Same currency but different decimal scales (e.g. pricing at 18 decimals, payment token at 6).
            // Without this branch, split amounts stay in pricing decimals while the cap comparison uses
            // payment decimals — causing orders-of-magnitude mis-scaling. This mirrors the same-currency
            // decimal adjustment in `normalizePaymentValue` (which handles the mint path).

            // Decode the per-tier breakdown so each amount can be rescaled individually.
            (uint16[] memory tierIds, uint256[] memory amounts) = abi.decode(convertedMetadata, (uint16[], uint256[]));

            // Re-accumulate the total from rescaled amounts to avoid rounding drift.
            convertedTotal = 0;
            for (uint256 i; i < amounts.length;) {
                // Scale each amount from pricing decimals to payment decimals.
                if (context.amount.decimals > pricingDecimals) {
                    // Payment has more decimals — multiply to add precision (e.g. 6→18: multiply by 10^12).
                    amounts[i] = amounts[i] * (10 ** (context.amount.decimals - pricingDecimals));
                } else {
                    // Payment has fewer decimals — divide to remove precision (e.g. 18→6: divide by 10^12).
                    amounts[i] = amounts[i] / (10 ** (pricingDecimals - context.amount.decimals));
                }
                convertedTotal += amounts[i];

                unchecked {
                    ++i;
                }
            }

            // Re-encode with the rescaled amounts.
            convertedMetadata = abi.encode(tierIds, amounts);
        }

        // Cap the total at the actual payment value. Pay credits fund NFT minting (virtual), but splits
        // require real tokens to distribute. Without this cap, a user with sufficient pay credits but
        // insufficient ETH would revert because the terminal can't forward more than what was actually paid.
        if (convertedTotal > context.amount.value) {
            // Proportionally reduce each per-tier amount to stay in sync with the capped total.
            if (convertedMetadata.length != 0) {
                (uint16[] memory tierIds, uint256[] memory amounts) =
                    abi.decode(convertedMetadata, (uint16[], uint256[]));
                uint256 uncappedTotal = convertedTotal;
                convertedTotal = 0;
                for (uint256 i; i < amounts.length;) {
                    // Scale down: amount * amountValue / originalTotal.
                    amounts[i] = mulDiv({x: amounts[i], y: context.amount.value, denominator: uncappedTotal});
                    convertedTotal += amounts[i];

                    unchecked {
                        ++i;
                    }
                }
                convertedMetadata = abi.encode(tierIds, amounts);
            } else {
                // Clamp the total to the payment value.
                convertedTotal = context.amount.value;
            }
        }
    }

    //*********************************************************************//
    // ----------------------- private helpers --------------------------- //
    //*********************************************************************//

    /// @notice Distributes funds for a single tier's split group.
    /// @dev Edge case: if both `_sendPayoutToSplit` returns false (reverting hook/terminal/beneficiary) AND the
    /// subsequent `addToBalanceOf` call also reverts for the leftover amount, native ETH will remain stranded in the
    /// hook contract with no recovery path. This requires two independent external call failures for the same split
    /// payout and is a pre-existing documented edge case. ERC-20 tokens are not affected because failed
    /// `addToBalanceOf` calls reset the approval. ERC-20 tokens remain in the hook contract. There is no built-in
    /// recovery mechanism.
    function _distributeSingleSplit(
        IJBDirectory directory,
        IJBSplits splitsContract,
        uint256 projectId,
        address token,
        uint256 groupId,
        uint256 amount,
        uint256 decimals
    )
        private
    {
        JBSplit[] memory tierSplits = splitsContract.splitsOf({projectId: projectId, rulesetId: 0, groupId: groupId});

        bool isNativeToken = token == JBConstants.NATIVE_TOKEN;
        uint256 leftoverPercentage = JBConstants.SPLITS_TOTAL_PERCENT;
        uint256 leftoverAmount = amount;
        amount = 0;

        for (uint256 j; j < tierSplits.length;) {
            uint256 payoutAmount =
                mulDiv({x: leftoverAmount, y: tierSplits[j].percent, denominator: leftoverPercentage});
            if (payoutAmount != 0) {
                unchecked {
                    leftoverAmount -= payoutAmount;
                }
                // On failure, don't re-add to leftoverAmount — this prevents inflating later recipients.
                // Failed amounts accumulate as the gap between `amount` and `leftoverAmount + total sent`.
                // After the loop, we re-add leftoverPercentage-based residual naturally.
                if (!_sendPayoutToSplit({
                        directory: directory,
                        split: tierSplits[j],
                        token: token,
                        amount: payoutAmount,
                        projectId: projectId,
                        groupId: groupId,
                        decimals: decimals
                    })) {
                    // Payout failed — route to project balance by returning to leftover after the loop.
                    // We add back to `amount` (parameter, no longer used for its original purpose).
                    unchecked {
                        amount += payoutAmount;
                    }
                }
            }
            unchecked {
                leftoverPercentage -= tierSplits[j].percent;
                ++j;
            }
        }

        // Route failed payout amounts to the project's balance.
        leftoverAmount += amount;

        if (leftoverAmount != 0) {
            IJBTerminal terminal = directory.primaryTerminalOf({projectId: projectId, token: token});
            // Revert if there are leftover funds but no terminal to route them to.
            if (address(terminal) == address(0)) {
                revert JB721TiersHookLib_NoTerminalForLeftover({
                    projectId: projectId, token: token, leftoverAmount: leftoverAmount
                });
            }
            if (isNativeToken) {
                try terminal.addToBalanceOf{value: leftoverAmount}({
                    projectId: projectId,
                    token: token,
                    amount: leftoverAmount,
                    shouldReturnHeldFees: false,
                    memo: "",
                    metadata: bytes("")
                }) {}
                catch (bytes memory reason) {
                    revert JB721TiersHookLib_SplitFallbackFailed({
                        projectId: projectId, token: token, amount: leftoverAmount, reason: reason
                    });
                }
            } else {
                SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: leftoverAmount});
                try terminal.addToBalanceOf({
                    projectId: projectId,
                    token: token,
                    amount: leftoverAmount,
                    shouldReturnHeldFees: false,
                    memo: "",
                    metadata: bytes("")
                }) {}
                catch (bytes memory reason) {
                    // Reset approval on failure.
                    SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: 0});
                    revert JB721TiersHookLib_SplitFallbackFailed({
                        projectId: projectId, token: token, amount: leftoverAmount, reason: reason
                    });
                }
            }
        }
    }

    /// @notice Sends a payout to a split recipient.
    /// @return sent Whether the funds were actually sent. Returns false if the split has no valid recipient
    /// (no hook, no projectId, and no beneficiary), so the caller can route the funds elsewhere.
    function _sendPayoutToSplit(
        IJBDirectory directory,
        JBSplit memory split,
        address token,
        uint256 amount,
        uint256 projectId,
        uint256 groupId,
        uint256 decimals
    )
        private
        returns (bool sent)
    {
        bool isNativeToken = token == JBConstants.NATIVE_TOKEN;

        // If the split has a hook, send the funds there.
        if (split.hook != IJBSplitHook(address(0))) {
            JBSplitHookContext memory context = JBSplitHookContext({
                token: token, amount: amount, decimals: decimals, projectId: projectId, groupId: groupId, split: split
            });

            if (isNativeToken) {
                // Wrap in try-catch so a reverting hook doesn't brick all project payments.
                // On revert, ETH stays with the caller and we return false.
                try split.hook.processSplitWith{value: amount}(context) {
                    return true;
                } catch (bytes memory reason) {
                    emit SplitPayoutReverted({
                        projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                    });
                    return false;
                }
            } else {
                // ERC20: transfer tokens first, then call the hook callback.
                // We must return true regardless of whether the callback reverts because the
                // tokens have already left this contract via safeTransfer. Returning false would
                // cause the caller to skip subtracting this amount from leftoverAmount, leading
                // to a double-spend when the leftover is later sent to the project's balance.
                SafeERC20.safeTransfer({token: IERC20(token), to: address(split.hook), value: amount});
                try split.hook.processSplitWith(context) {}
                catch (bytes memory reason) {
                    emit SplitPayoutReverted({
                        projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                    });
                }
                return true;
            }
        } else if (split.projectId != 0) {
            IJBTerminal terminal = directory.primaryTerminalOf({projectId: split.projectId, token: token});
            if (address(terminal) == address(0)) return false;

            // Wrap terminal calls in try-catch to prevent a failing terminal from bricking payments.
            if (split.preferAddToBalance) {
                if (isNativeToken) {
                    try terminal.addToBalanceOf{value: amount}({
                        projectId: split.projectId,
                        token: token,
                        amount: amount,
                        shouldReturnHeldFees: false,
                        memo: "",
                        metadata: bytes("")
                    }) {
                        return true;
                    } catch (bytes memory reason) {
                        emit SplitPayoutReverted({
                            projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                        });
                        return false;
                    }
                } else {
                    SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: amount});
                    try terminal.addToBalanceOf({
                        projectId: split.projectId,
                        token: token,
                        amount: amount,
                        shouldReturnHeldFees: false,
                        memo: "",
                        metadata: bytes("")
                    }) {
                        return true;
                    } catch (bytes memory reason) {
                        // Reset approval on failure so tokens aren't left approved to the terminal.
                        SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: 0});
                        emit SplitPayoutReverted({
                            projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                        });
                        return false;
                    }
                }
            } else {
                if (isNativeToken) {
                    try terminal.pay{value: amount}({
                        projectId: split.projectId,
                        token: token,
                        amount: amount,
                        beneficiary: split.beneficiary,
                        minReturnedTokens: 0,
                        memo: "",
                        metadata: bytes("")
                    }) {
                        return true;
                    } catch (bytes memory reason) {
                        emit SplitPayoutReverted({
                            projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                        });
                        return false;
                    }
                } else {
                    SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: amount});
                    try terminal.pay({
                        projectId: split.projectId,
                        token: token,
                        amount: amount,
                        beneficiary: split.beneficiary,
                        minReturnedTokens: 0,
                        memo: "",
                        metadata: bytes("")
                    }) {
                        return true;
                    } catch (bytes memory reason) {
                        // Reset approval on failure so tokens aren't left approved to the terminal.
                        SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: 0});
                        emit SplitPayoutReverted({
                            projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                        });
                        return false;
                    }
                }
            }
        } else if (split.beneficiary != address(0)) {
            if (isNativeToken) {
                (bool success,) = split.beneficiary.call{value: amount}("");
                if (!success) return false;
            } else {
                // Use the same low-level call + returndata check as SafeERC20.safeTransfer, but return
                // false on failure instead of reverting. This handles non-standard tokens (e.g. USDT)
                // that return void, while routing failed transfers to the project's balance instead
                // of bricking all payments.
                (bool callSuccess, bytes memory returndata) =
                    address(token).call(abi.encodeCall(IERC20.transfer, (split.beneficiary, amount)));
                if (!callSuccess || (returndata.length != 0 && !abi.decode(returndata, (bool)))) return false;
            }
            return true;
        }
        // No projectId and no beneficiary — return false so the funds go to the project's balance.
        return false;
    }

    /// @notice Sets split groups in JBSplits for tiers that have splits configured.
    function _setSplitGroupsFor(
        IJBSplits splits,
        uint256 projectId,
        address hookAddress,
        JB721TierConfig[] memory tiersToAdd,
        uint256[] memory tierIdsAdded
    )
        private
    {
        uint256 splitGroupCount;
        for (uint256 i; i < tiersToAdd.length;) {
            if (tiersToAdd[i].splits.length != 0) splitGroupCount++;

            unchecked {
                ++i;
            }
        }
        if (splitGroupCount == 0) return;

        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](splitGroupCount);
        uint256 groupIndex;
        for (uint256 i; i < tiersToAdd.length;) {
            if (tiersToAdd[i].splits.length != 0) {
                splitGroups[groupIndex] = JBSplitGroup({
                    groupId: uint256(uint160(hookAddress)) | (tierIdsAdded[i] << 160), splits: tiersToAdd[i].splits
                });
                groupIndex++;
            }

            unchecked {
                ++i;
            }
        }
        splits.setSplitGroupsOf({projectId: projectId, rulesetId: 0, splitGroups: splitGroups});
    }
}
