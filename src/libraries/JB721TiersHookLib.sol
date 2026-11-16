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

    /// @notice Thrown when the fresh payment value does not cover the cost of credit-restricted tiers being minted.
    error JB721TiersHook_CantBuyWithCredits(uint256 restrictedCost, uint256 freshValue);

    /// @notice Thrown when funds are left over after minting but overspending is not allowed.
    error JB721TiersHook_Overspending(uint256 leftoverAmount);

    /// @notice Thrown when leftover funds must be routed to the project but it has no primary terminal for the token.
    error JB721TiersHookLib_HeldPayoutStillFailing(bytes32 heldPayoutId, uint256 amount);
    error JB721TiersHookLib_NoHeldPayout(bytes32 heldPayoutId);
    error JB721TiersHookLib_NoTerminalForLeftover(uint256 projectId, address token, uint256 leftoverAmount);

    /// @notice Thrown when the per-tier split amounts do not sum to the total amount forwarded by the terminal.
    error JB721TiersHookLib_SplitAmountMismatch(uint256 expectedAmount, uint256 actualAmount);

    /// @notice Thrown when routing leftover funds to the project's terminal reverts or under-consumes the allowance.
    error JB721TiersHookLib_SplitFallbackFailed(uint256 projectId, address token, uint256 amount, bytes reason);

    /// @notice Thrown when the decoded split metadata's tier ID and amount arrays have different lengths.
    error JB721TiersHookLib_SplitMetadataLengthMismatch(uint256 tierIdCount, uint256 amountCount);

    /// @notice Thrown when the ERC-20 amount actually received does not match the expected transfer amount.
    error JB721TiersHookLib_TokenTransferAmountMismatch(uint256 expectedAmount, uint256 receivedAmount);

    //*********************************************************************//
    // ------------------------------- events ---------------------------- //
    //*********************************************************************//

    /// @notice Emitted when a new tier is added.
    /// @param tierId The ID of the tier that was added.
    /// @param tier The configuration of the tier that was added.
    /// @param caller The address that called the function.
    event AddTier(uint256 indexed tierId, JB721TierConfig tier, address caller);

    /// @notice Emitted when a tier is removed.
    /// @param tierId The ID of the tier that was removed.
    /// @param caller The address that called the function.
    event RemoveTier(uint256 indexed tierId, address caller);

    /// @notice Emitted when a tier's discount percent is set.
    /// @param tierId The ID of the tier whose discount percent was set.
    /// @param discountPercent The new discount percent.
    /// @param caller The address that called the function.
    event SetDiscountPercent(uint256 indexed tierId, uint256 discountPercent, address caller);

    /// @notice A tier split's recipient reverted, so the amount is held for the split until a retry succeeds.
    /// @param projectId The ID of the project the payout is from.
    /// @param token The token of the payout.
    /// @param groupId The split group the split belongs to.
    /// @param decimals The decimals of `token`, as forwarded into the split hook context.
    /// @param split The split the amount is held for.
    /// @param amount The amount held.
    /// @param reason The revert reason, or the token's return data for a rejected transfer.
    event HoldPayout(
        uint256 indexed projectId,
        address indexed token,
        uint256 groupId,
        uint256 decimals,
        JBSplit split,
        uint256 amount,
        bytes reason
    );

    /// @notice A held tier split payout was retried and delivered.
    /// @param projectId The ID of the project the payout is from.
    /// @param token The token of the payout.
    /// @param groupId The split group the split belongs to.
    /// @param split The split that was paid.
    /// @param amount The amount that was held.
    /// @param sent The amount the recipient took; the rest went to the project's balance.
    /// @param caller The address that retried the payout.
    event ProcessHeldPayout(
        uint256 indexed projectId,
        address indexed token,
        uint256 groupId,
        JBSplit split,
        uint256 amount,
        uint256 sent,
        address caller
    );

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Handles the full tier adjustment logic: removes tiers, adds tiers, emits events, and sets splits.
    /// @dev Inlined into the hook, so events are emitted from the hook's address.
    /// @param store The 721 tiers hook store.
    /// @param splits The splits contract to register tier split groups in.
    /// @param projectId The project ID.
    /// @param hookAddress The hook address; forms the low 160 bits of each tier's split group ID.
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
        internal
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
    /// @param heldPayoutOf The hook's held payout ledger, written when a split's recipient reverts.
    /// @param directory The directory to look up terminals.
    /// @param splits The splits contract to read tier split groups from.
    /// @param projectId The project ID of the hook.
    /// @param token The token to distribute.
    /// @param amount The total amount to distribute.
    /// @param decimals The token decimals.
    /// @param encodedSplitData The encoded per-tier breakdown from hookMetadata.
    function distributeAll(
        mapping(bytes32 heldPayoutId => uint256 amount) storage heldPayoutOf,
        IJBDirectory directory,
        IJBSplits splits,
        uint256 projectId,
        address token,
        uint256 amount,
        uint256 decimals,
        bytes memory encodedSplitData
    )
        internal
    {
        // `encodedSplitData` is terminal-forwarded hook metadata. Each tier ID must have exactly one explicit amount so
        // later split-group routing cannot pair a tier with the wrong value or silently ignore trailing data.
        (uint16[] memory tierIds, uint256[] memory amounts) = abi.decode(encodedSplitData, (uint16[], uint256[]));
        if (tierIds.length != amounts.length) {
            revert JB721TiersHookLib_SplitMetadataLengthMismatch({
                tierIdCount: tierIds.length, amountCount: amounts.length
            });
        }

        // The terminal tells the hook how much value was forwarded. Require the per-tier split metadata to account for
        // all of it before any transfers happen, otherwise malformed metadata could over-distribute, under-distribute,
        // or leave funds stuck in the hook.
        uint256 totalAmount;
        for (uint256 i; i < amounts.length;) {
            totalAmount += amounts[i];
            unchecked {
                ++i;
            }
        }
        if (totalAmount != amount) {
            revert JB721TiersHookLib_SplitAmountMismatch({expectedAmount: amount, actualAmount: totalAmount});
        }

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

        for (uint256 i; i < tierIds.length;) {
            if (amounts[i] == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            uint256 groupId = _groupIdOf(tierIds[i]);
            _distributeSingleSplit({
                heldPayoutOf: heldPayoutOf,
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

    /// @notice Retries a held tier split payout.
    /// @dev Permissionless. Runs the same delivery code as the original payout; if the recipient fails again the
    /// amount is re-held by that code, which this function turns into a revert so the ledger is left as it was.
    /// @param heldPayoutOf The hook's held payout ledger.
    /// @param directory The directory used to resolve primary terminals.
    /// @param projectId The project ID the payout is from.
    /// @param token The token of the payout.
    /// @param tierId The tier whose split group the split belongs to.
    /// @param decimals The decimals of `token`, as emitted in `HoldPayout`.
    /// @param split The held split, as emitted in `HoldPayout`.
    function processHeldPayout(
        mapping(bytes32 heldPayoutId => uint256 amount) storage heldPayoutOf,
        IJBDirectory directory,
        uint256 projectId,
        address token,
        uint16 tierId,
        uint256 decimals,
        JBSplit calldata split
    )
        internal
    {
        uint256 groupId = _groupIdOf(tierId);
        bytes32 heldPayoutId = _heldPayoutIdOf({token: token, groupId: groupId, decimals: decimals, split: split});
        uint256 amount = heldPayoutOf[heldPayoutId];
        if (amount == 0) revert JB721TiersHookLib_NoHeldPayout({heldPayoutId: heldPayoutId});
        delete heldPayoutOf[heldPayoutId];

        uint256 sent = _sendPayoutToSplit({
            heldPayoutOf: heldPayoutOf,
            directory: directory,
            context: JBSplitHookContext({
                token: token, amount: amount, decimals: decimals, projectId: projectId, groupId: groupId, split: split
            })
        });
        if (heldPayoutOf[heldPayoutId] != 0) {
            revert JB721TiersHookLib_HeldPayoutStillFailing({heldPayoutId: heldPayoutId, amount: amount});
        }

        // Whatever the recipient did not take goes to the project, as it would have in the original payment.
        _routeLeftover({directory: directory, projectId: projectId, token: token, leftoverAmount: amount - sent});

        emit ProcessHeldPayout({
            projectId: projectId,
            token: token,
            groupId: groupId,
            split: split,
            amount: amount,
            sent: sent,
            caller: msg.sender
        });
    }

    /// @notice Prepares NFT minting data for a payment: combines credits, decodes metadata, records mint, and checks
    /// overspending.
    /// @dev Inlined into the hook; uses address(this) as the hook address.
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
        internal
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
        internal
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
        internal
    {
        emit SetDiscountPercent({tierId: tierId, discountPercent: discountPercent, caller: caller});
        store.recordSetDiscountPercentOf({tierId: tierId, discountPercent: discountPercent});
    }

    //*********************************************************************//
    // ----------------------- external views ---------------------------- //
    //*********************************************************************//

    /// @notice Computes split amounts, weight adjustment, and resolved beneficiary for a payment.
    /// @dev Inlined into the hook; uses address(this) as the hook address.
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
        internal
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
            splitCreditWeight = mulDiv({x: context.weight, y: totalSplitAmount, denominator: context.amount.value});
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
        internal
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
        internal
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

    /// @notice Approves `terminal` to spend `amount` of `token`, calls `addToBalanceOf`, then revokes any
    /// unconsumed allowance and reports the actual amount consumed via the allowance delta.
    /// @dev Allowance-delta consumption protects against terminals that return successfully without pulling
    /// the full granted amount, and the unconditional final `forceApprove(..., 0)` ensures no stale allowance
    /// is left behind on either the success or failure path.
    /// @param terminal The terminal to call.
    /// @param token The ERC-20 token. Native must not be passed here.
    /// @param projectId The destination project ID.
    /// @param amount The amount to grant as allowance and request the terminal to pull.
    /// @return consumed The amount actually consumed by the terminal (0 on revert; otherwise
    /// `amount - remainingAllowance` after the call).
    /// @return succeeded Whether the terminal call returned without reverting.
    /// @return failureReason The revert reason from the terminal call, or empty bytes if the call succeeded.
    function _approveAndAddToBalance(
        IJBTerminal terminal,
        address token,
        uint256 projectId,
        uint256 amount
    )
        private
        returns (uint256 consumed, bool succeeded, bytes memory failureReason)
    {
        // Grant the terminal allowance to pull up to `amount` of `token` from this contract. `forceApprove`
        // sets the allowance to exactly `amount` regardless of any prior allowance, so a leftover non-zero
        // allowance from a previous failed call cannot inflate this one.
        SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: amount});

        // Call the terminal's `addToBalanceOf` inside try/catch so a reverting terminal can't brick the
        // surrounding payment. The terminal is expected to `transferFrom` against the allowance set above.
        try terminal.addToBalanceOf({
            projectId: projectId,
            token: token,
            amount: amount,
            // Don't release any held fees on this call — fee returns are handled separately.
            shouldReturnHeldFees: false,
            // No memo or metadata is forwarded; the leftover routing is opaque to off-chain consumers.
            memo: "",
            metadata: bytes("")
        }) {
            // The terminal returned without reverting. The actual amount it consumed is measured below
            // via the allowance delta — `succeeded` only records that there was no revert to report.
            succeeded = true;
        } catch (bytes memory reason) {
            // The terminal reverted. Capture the reason so the caller can surface it via the
            // `SplitPayoutReverted` event (or, for the leftover fallback, the
            // `JB721TiersHookLib_SplitFallbackFailed` error) without re-throwing here.
            failureReason = reason;
        }

        // On success, compute how much the terminal actually pulled. The post-call allowance equals
        // `amount - actuallyConsumed` (since `forceApprove` set the pre-call allowance to `amount`), so
        // `consumed = amount - postAllowance`. On failure, `succeeded` is `false` and `consumed` stays at
        // its default `0`, which lets the caller route the full `amount` to the project's leftover balance.
        if (succeeded) {
            // Safe to use `unchecked`: `postAllowance` cannot exceed `amount` because the terminal can
            // only decrement (via `transferFrom`) the allowance we just set to `amount`.
            unchecked {
                consumed = amount - IERC20(token).allowance({owner: address(this), spender: address(terminal)});
            }
        }

        // Unconditionally revoke any remaining allowance. This is the load-bearing safety step — without
        // it, a terminal that returns successfully without pulling the full `amount` would leave a stale
        // non-zero allowance that the terminal could drain later. Running on both the success and failure
        // paths means no allowance ever leaks out of this function.
        SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: 0});
    }

    /// @notice Approves `terminal` to spend `amount` of `token`, calls `pay`, then revokes any unconsumed
    /// allowance and reports the actual amount consumed via the allowance delta.
    /// @dev Mirrors `_approveAndAddToBalance` for the `pay` entry point.
    /// @param terminal The terminal to call.
    /// @param token The ERC-20 token. Native must not be passed here.
    /// @param projectId The destination project ID.
    /// @param amount The amount to grant as allowance and request the terminal to pull.
    /// @param beneficiary The beneficiary for the `pay` call.
    /// @return consumed The amount actually consumed by the terminal.
    /// @return succeeded Whether the terminal call returned without reverting.
    /// @return failureReason The revert reason from the terminal call, or empty bytes on success.
    function _approveAndPay(
        IJBTerminal terminal,
        address token,
        uint256 projectId,
        uint256 amount,
        address payable beneficiary
    )
        private
        returns (uint256 consumed, bool succeeded, bytes memory failureReason)
    {
        // Grant the terminal allowance to pull up to `amount` of `token` from this contract. `forceApprove`
        // sets the allowance to exactly `amount` regardless of any prior allowance, so a leftover non-zero
        // allowance from a previous failed call cannot inflate this one.
        SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: amount});

        // Call the terminal's `pay` inside try/catch so a reverting terminal can't brick the surrounding
        // payment. The terminal is expected to `transferFrom` against the allowance set above and mint
        // project tokens to `beneficiary` in return.
        try terminal.pay({
            projectId: projectId,
            token: token,
            amount: amount,
            beneficiary: beneficiary,
            // No minimum is enforced on the terminal-side mint — the split-level minimum (if any) is
            // enforced by the caller before reaching this helper.
            minReturnedTokens: 0,
            // No memo or metadata is forwarded; the leftover routing is opaque to off-chain consumers.
            memo: "",
            metadata: bytes("")
        }) {
            // The terminal returned without reverting. The actual amount it consumed is measured below
            // via the allowance delta — `succeeded` only records that there was no revert to report.
            succeeded = true;
        } catch (bytes memory reason) {
            // The terminal reverted. Capture the reason so the caller can surface it via the
            // `SplitPayoutReverted` event without re-throwing here.
            failureReason = reason;
        }

        // On success, compute how much the terminal actually pulled. The post-call allowance equals
        // `amount - actuallyConsumed` (since `forceApprove` set the pre-call allowance to `amount`), so
        // `consumed = amount - postAllowance`. On failure, `succeeded` is `false` and `consumed` stays at
        // its default `0`, which lets the caller route the full `amount` to the project's leftover balance.
        if (succeeded) {
            // Safe to use `unchecked`: `postAllowance` cannot exceed `amount` because the terminal can
            // only decrement (via `transferFrom`) the allowance we just set to `amount`.
            unchecked {
                consumed = amount - IERC20(token).allowance({owner: address(this), spender: address(terminal)});
            }
        }

        // Unconditionally revoke any remaining allowance. This is the load-bearing safety step — without
        // it, a terminal that returns successfully without pulling the full `amount` would leave a stale
        // non-zero allowance that the terminal could drain later. Running on both the success and failure
        // paths means no allowance ever leaks out of this function.
        SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: 0});
    }

    /// @notice Distributes funds for a single tier's split group.
    /// @dev `_sendPayoutToSplit` returns the actual amount that left this contract — `payoutAmount` on full
    /// success, `0` when the split fully fails (revert or missing recipient), or a partial value when an ERC-20
    /// split hook pulled some but not all of its allowance. The unsent portion accumulates into `amount` and is
    /// routed to the project's primary terminal via `addToBalanceOf` after the loop. If that fallback also
    /// reverts and the token is native ETH, the unsent ETH is stuck in this contract with no recovery path.
    /// For ERC-20 the approval is reset on `addToBalanceOf` failure so the terminal cannot pull later.
    /// @param directory The directory used to resolve the primary terminal for the leftover fallback.
    /// @param splitsContract The splits contract used to look up the tier's split group.
    /// @param projectId The project ID whose primary terminal receives the leftover.
    /// @param token The token being distributed. Use `JBConstants.NATIVE_TOKEN` for ETH.
    /// @param groupId The split group ID identifying the tier whose splits to read.
    /// @param amount The total amount available to distribute across the tier's splits.
    /// @param decimals The decimals of `token`, forwarded into each split hook context.
    function _distributeSingleSplit(
        mapping(bytes32 heldPayoutId => uint256 amount) storage heldPayoutOf,
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
                // `_sendPayoutToSplit` returns the actual amount that left this contract (0 on full failure,
                // a partial value when a split hook pulled some but not all of its allowance, or `payoutAmount`
                // on full success). Add the unsent portion to `amount` so it routes to the project's balance
                // after the loop. The subtraction is safe — the function invariantly returns at most
                // `payoutAmount` (allowance bounded for ERC-20, value bounded for ETH, else all-or-nothing).
                unchecked {
                    amount += payoutAmount
                        - _sendPayoutToSplit({
                            heldPayoutOf: heldPayoutOf,
                            directory: directory,
                            context: JBSplitHookContext({
                                token: token,
                                amount: payoutAmount,
                                decimals: decimals,
                                projectId: projectId,
                                groupId: groupId,
                                split: tierSplits[j]
                            })
                        });
                }
            }
            unchecked {
                leftoverPercentage -= tierSplits[j].percent;
                ++j;
            }
        }

        // Route failed payout amounts to the project's balance.
        leftoverAmount += amount;

        _routeLeftover({directory: directory, projectId: projectId, token: token, leftoverAmount: leftoverAmount});
    }

    /// @notice Routes an amount nothing else consumed to the project's primary terminal for the token.
    /// @dev Reverts if there is no terminal or the add to balance fails, so funds never stay stuck in the hook.
    /// @param directory The directory used to resolve the primary terminal.
    /// @param projectId The project ID whose primary terminal receives the leftover.
    /// @param token The token being routed. Use `JBConstants.NATIVE_TOKEN` for ETH.
    /// @param leftoverAmount The amount to route. Nothing happens when zero.
    function _routeLeftover(IJBDirectory directory, uint256 projectId, address token, uint256 leftoverAmount) private {
        bool isNativeToken = token == JBConstants.NATIVE_TOKEN;

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
                // Allowance-delta + unconditional cleanup: a terminal that returns successfully without pulling
                // the full allowance would otherwise leave funds stranded in this library/hook and leak a
                // non-zero allowance to the terminal. Fail closed: revert if either the call reverts OR the
                // terminal under-consumed the granted allowance.
                (uint256 consumed, bool succeeded, bytes memory failureReason) = _approveAndAddToBalance({
                    terminal: terminal, token: token, projectId: projectId, amount: leftoverAmount
                });
                if (!succeeded || consumed != leftoverAmount) {
                    revert JB721TiersHookLib_SplitFallbackFailed({
                        projectId: projectId, token: token, amount: leftoverAmount, reason: failureReason
                    });
                }
            }
        }
    }

    /// @notice Sends a payout to a single split recipient.
    /// @dev Recipient resolution order: (1) `split.hook` if set; (2) `split.projectId` (uses
    /// `split.preferAddToBalance` to choose between `addToBalanceOf` and `pay` on the primary terminal);
    /// (3) `split.beneficiary` for a direct transfer. All-or-nothing for terminal and beneficiary paths;
    /// the split-hook path supports partial pulls via allowance for ERC-20 and balance-delta for ETH.
    /// A recipient that reverts, or rejects a transfer, has the whole amount held for it in `heldPayoutOf` and
    /// `processHeldPayout` retries it: the gas a payer picks must never move a tier split's share into the project's
    /// own balance. A missing recipient (no terminal, no beneficiary) is not a revert and still routes to the project.
    /// @param heldPayoutOf The hook's held payout ledger.
    /// @param directory The directory used to resolve the primary terminal when the split targets a project.
    /// @param context The split and its payout: token, amount, decimals, project ID and group ID.
    /// @return sent The amount that left this contract or is now held for the split. Equals the amount on a fully
    /// successful or held payout, `0` for a missing recipient, and a partial value when a split hook pulled some but
    /// not all of its ERC-20 allowance (or returned some native ETH back to this contract). The caller routes the
    /// rest to the project's leftover balance.
    function _sendPayoutToSplit(
        mapping(bytes32 heldPayoutId => uint256 amount) storage heldPayoutOf,
        IJBDirectory directory,
        JBSplitHookContext memory context
    )
        private
        returns (uint256 sent)
    {
        if (context.split.hook != IJBSplitHook(address(0))) {
            return _sendToHook({heldPayoutOf: heldPayoutOf, context: context});
        }
        if (context.split.projectId != 0) {
            return _sendToProject({heldPayoutOf: heldPayoutOf, directory: directory, context: context});
        }
        if (context.split.beneficiary != address(0)) {
            return _sendToBeneficiary({heldPayoutOf: heldPayoutOf, context: context});
        }
        // No projectId and no beneficiary: the funds go to the project's balance.
        return 0;
    }

    /// @notice Sends a split's payout to its split hook.
    /// @param heldPayoutOf The hook's held payout ledger.
    /// @param context The split and its payout.
    /// @return sent The amount the hook took, or the whole amount if the hook reverted and the payout is now held.
    function _sendToHook(
        mapping(bytes32 heldPayoutId => uint256 amount) storage heldPayoutOf,
        JBSplitHookContext memory context
    )
        private
        returns (uint256 sent)
    {
        IJBSplitHook hook = context.split.hook;
        uint256 amount = context.amount;

        if (context.token == JBConstants.NATIVE_TOKEN) {
            // ETH is pushed via `{value: amount}`. On success the hook usually keeps the full amount, but if it
            // sends some ETH back via low-level call the balance-delta reports the actual amount that left this
            // contract; the unsent portion routes to the project.
            uint256 ethBefore = address(this).balance;
            try hook.processSplitWith{value: amount}(context) {}
            catch (bytes memory reason) {
                return _hold({heldPayoutOf: heldPayoutOf, context: context, reason: reason});
            }
            return ethBefore - address(this).balance;
        }

        // ERC20: grant the hook an allowance, call it, revoke any unconsumed allowance and report the amount
        // actually pulled via balance-delta. A hook that pulls less keeps what it pulled and the rest routes to the
        // project. Mirrors the controller's allowance pattern for reserved-token splits.
        IERC20 token = IERC20(context.token);
        uint256 balanceBefore = token.balanceOf(address(this));
        SafeERC20.forceApprove({token: token, spender: address(hook), value: amount});
        try hook.processSplitWith(context) {}
        catch (bytes memory reason) {
            SafeERC20.forceApprove({token: token, spender: address(hook), value: 0});
            return _hold({heldPayoutOf: heldPayoutOf, context: context, reason: reason});
        }
        SafeERC20.forceApprove({token: token, spender: address(hook), value: 0});
        return balanceBefore - token.balanceOf(address(this));
    }

    /// @notice Sends a split's payout to another project's primary terminal.
    /// @param heldPayoutOf The hook's held payout ledger.
    /// @param directory The directory used to resolve the primary terminal.
    /// @param context The split and its payout.
    /// @return sent The amount the terminal took, the whole amount if it reverted and the payout is now held, or 0
    /// if the project has no terminal for the token.
    function _sendToProject(
        mapping(bytes32 heldPayoutId => uint256 amount) storage heldPayoutOf,
        IJBDirectory directory,
        JBSplitHookContext memory context
    )
        private
        returns (uint256 sent)
    {
        IJBTerminal terminal = directory.primaryTerminalOf({projectId: context.split.projectId, token: context.token});
        if (address(terminal) == address(0)) return 0;

        // Terminal calls are all-or-nothing for native ETH; for ERC-20 the allowance delta reports what the terminal
        // actually pulled.
        bool succeeded;
        bytes memory failureReason;
        if (context.token == JBConstants.NATIVE_TOKEN) {
            sent = context.amount;
            (succeeded, failureReason) =
                _sendNativeToTerminal({terminal: terminal, split: context.split, amount: context.amount});
        } else if (context.split.preferAddToBalance) {
            (sent, succeeded, failureReason) = _approveAndAddToBalance({
                terminal: terminal, token: context.token, projectId: context.split.projectId, amount: context.amount
            });
        } else {
            (sent, succeeded, failureReason) = _approveAndPay({
                terminal: terminal,
                token: context.token,
                projectId: context.split.projectId,
                amount: context.amount,
                beneficiary: context.split.beneficiary
            });
        }

        if (!succeeded) return _hold({heldPayoutOf: heldPayoutOf, context: context, reason: failureReason});
        return sent;
    }

    /// @notice Sends a split's payout straight to its beneficiary.
    /// @param heldPayoutOf The hook's held payout ledger.
    /// @param context The split and its payout.
    /// @return The whole amount: either transferred, or held because the beneficiary rejected it.
    function _sendToBeneficiary(
        mapping(bytes32 heldPayoutId => uint256 amount) storage heldPayoutOf,
        JBSplitHookContext memory context
    )
        private
        returns (uint256)
    {
        bool success;
        bytes memory returndata;
        if (context.token == JBConstants.NATIVE_TOKEN) {
            (success, returndata) = context.split.beneficiary.call{value: context.amount}("");
        } else {
            // Same low-level call + returndata check as SafeERC20.safeTransfer, holding instead of reverting so
            // non-standard tokens (e.g. USDT) that return void still work and a rejected transfer does not brick the
            // whole payment.
            (success, returndata) =
                context.token.call(abi.encodeCall(IERC20.transfer, (context.split.beneficiary, context.amount)));
            if (success && returndata.length != 0 && !abi.decode(returndata, (bool))) success = false;
        }
        if (!success) return _hold({heldPayoutOf: heldPayoutOf, context: context, reason: returndata});
        return context.amount;
    }

    /// @notice Sends native ETH to a project's terminal, by `addToBalanceOf` or `pay` as the split prefers.
    /// @dev Kept out of `_sendPayoutToSplit` so the try/catch has its own stack frame.
    /// @param terminal The destination project's terminal.
    /// @param split The split being paid; its `projectId`, `beneficiary` and `preferAddToBalance` are used.
    /// @param amount The amount of ETH to send.
    /// @return succeeded Whether the terminal call returned without reverting.
    /// @return failureReason The revert reason when it did not.
    function _sendNativeToTerminal(
        IJBTerminal terminal,
        JBSplit memory split,
        uint256 amount
    )
        private
        returns (bool succeeded, bytes memory failureReason)
    {
        if (split.preferAddToBalance) {
            try terminal.addToBalanceOf{value: amount}({
                projectId: split.projectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: amount,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: bytes("")
            }) {
                succeeded = true;
            } catch (bytes memory reason) {
                failureReason = reason;
            }
        } else {
            try terminal.pay{value: amount}({
                projectId: split.projectId,
                token: JBConstants.NATIVE_TOKEN,
                amount: amount,
                beneficiary: split.beneficiary,
                minReturnedTokens: 0,
                memo: "",
                metadata: bytes("")
            }) {
                succeeded = true;
            } catch (bytes memory reason) {
                failureReason = reason;
            }
        }
    }

    /// @notice Holds a tier split's payout for a later `processHeldPayout`.
    /// @param heldPayoutOf The hook's held payout ledger.
    /// @param context The split's hook context: token, amount, decimals, project ID, group ID and split.
    /// @param reason The revert reason.
    /// @return The amount held, so callers can report it as sent.
    function _hold(
        mapping(bytes32 heldPayoutId => uint256 amount) storage heldPayoutOf,
        JBSplitHookContext memory context,
        bytes memory reason
    )
        private
        returns (uint256)
    {
        heldPayoutOf[
            _heldPayoutIdOf({
                token: context.token, groupId: context.groupId, decimals: context.decimals, split: context.split
            })
        ] += context.amount;

        emit HoldPayout({
            projectId: context.projectId,
            token: context.token,
            groupId: context.groupId,
            decimals: context.decimals,
            split: context.split,
            amount: context.amount,
            reason: reason
        });

        return context.amount;
    }

    /// @notice The split group ID of a tier: the hook address in the low 160 bits and the tier ID above it.
    /// @dev Inlined into the hook, so `address(this)` is the hook.
    /// @param tierId The tier ID.
    /// @return The split group ID.
    function _groupIdOf(uint16 tierId) private view returns (uint256) {
        return uint256(uint160(address(this))) | (uint256(tierId) << 160);
    }

    /// @notice The key a held tier split payout is stored under.
    /// @param token The token of the payout.
    /// @param groupId The split group the split belongs to.
    /// @param decimals The decimals of `token`.
    /// @param split The split the payout was for.
    /// @return The held payout ID.
    function _heldPayoutIdOf(
        address token,
        uint256 groupId,
        uint256 decimals,
        JBSplit memory split
    )
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(token, groupId, decimals, split));
    }

    /// @notice Sets split groups in JBSplits for tiers that have splits configured.
    /// @dev Walks `tiersToAdd` in parallel with `tierIdsAdded`. Tiers with an empty `splits` array are skipped,
    /// so only tiers that opt into split distribution allocate a group. The group ID is packed as
    /// `hookAddress | (tierId << 160)` so each tier owns a distinct group within the hook's namespace.
    /// @param splits The splits contract that stores the per-tier groups.
    /// @param projectId The project ID owning the splits.
    /// @param hookAddress The 721 hook address; forms the low 160 bits of each group ID.
    /// @param tiersToAdd The tier configurations being recorded; each may carry its own `splits` array.
    /// @param tierIdsAdded The tier IDs assigned at recording time, in the same order as `tiersToAdd`.
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
