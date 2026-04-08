// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";

import {IJB721TiersHookStore} from "../interfaces/IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "../interfaces/IJB721TokenUriResolver.sol";
import {JB721TierConfig} from "../structs/JB721TierConfig.sol";
import {JB721Constants} from "./JB721Constants.sol";
import {JBIpfsDecoder} from "./JBIpfsDecoder.sol";

/// @notice External library for JB721TiersHook operations extracted to stay within the EIP-170 contract size limit.
/// @dev Handles tier adjustments, split calculations, price normalization, and split fund distribution.
library JB721TiersHookLib {
    error JB721TiersHookLib_NoTerminalForLeftover(uint256 projectId, address token, uint256 leftoverAmount);
    error JB721TiersHookLib_SplitFallbackFailed(uint256 projectId, address token, uint256 amount, bytes reason);
    error JB721TiersHookLib_TokenTransferAmountMismatch(uint256 expectedAmount, uint256 receivedAmount);
    event AddTier(uint256 indexed tierId, JB721TierConfig tier, address caller);
    event RemoveTier(uint256 indexed tierId, address caller);
    event SplitPayoutReverted(uint256 indexed projectId, JBSplit split, uint256 amount, bytes reason, address caller);

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
            // slither-disable-next-line reentrancy-events
            store.recordRemoveTierIds(tierIdsToRemove);
        }

        // Add tiers.
        if (tiersToAdd.length != 0) {
            uint256[] memory tierIdsAdded = store.recordAddTiers(tiersToAdd);

            // slither-disable-next-line reentrancy-events
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
            // slither-disable-next-line reentrancy-events
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

    /// @notice Calculates per-tier split amounts for a pay event.
    /// @param store The 721 tiers hook store.
    /// @param hook The hook address.
    /// @param metadataIdTarget The metadata ID target for resolving pay metadata.
    /// @param metadata The payer metadata.
    /// @return totalSplitAmount The total amount to forward for splits.
    /// @return hookMetadata Encoded per-tier breakdown (tierIds, amounts) for afterPay.
    function calculateSplitAmounts(
        IJB721TiersHookStore store,
        address hook,
        address metadataIdTarget,
        bytes calldata metadata
    )
        external
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
            // slither-disable-next-line calls-loop
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
    function calculateWeight(
        uint256 contextWeight,
        uint256 amountValue,
        uint256 totalSplitAmount,
        IJB721TiersHookStore store,
        address hook
    )
        external
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
    /// @dev Combines currency conversion and cap into one external call to keep hook bytecode under EIP-170.
    /// @param totalSplitAmount The total split amount in tier pricing denomination.
    /// @param splitMetadata The encoded per-tier breakdown (tierIds, amounts).
    /// @param packedPricingContext The packed pricing context (currency in bits 0-31, decimals in bits 32-39).
    /// @param prices The prices contract used for currency conversion.
    /// @param projectId The project ID.
    /// @param amountCurrency The payment amount currency.
    /// @param amountDecimals The payment amount decimals.
    /// @param amountValue The actual payment value (used as the cap).
    /// @return convertedTotal The total split amount after conversion and capping.
    /// @return convertedMetadata The re-encoded per-tier breakdown with adjusted amounts.
    function convertAndCapSplitAmounts(
        uint256 totalSplitAmount,
        bytes memory splitMetadata,
        uint256 packedPricingContext,
        IJBPrices prices,
        uint256 projectId,
        uint256 amountCurrency,
        uint256 amountDecimals,
        uint256 amountValue
    )
        external
        view
        returns (uint256 convertedTotal, bytes memory convertedMetadata)
    {
        // Start from the input values; conversion and capping modify them in-place below.
        convertedTotal = totalSplitAmount;
        convertedMetadata = splitMetadata;

        // Convert each per-tier amount from the tier pricing currency to the payment currency.
        // forge-lint: disable-next-line(unsafe-typecast)
        if (amountCurrency != uint256(uint32(packedPricingContext))) {
            // No price oracle available — return 0 to skip the split rather than forwarding an unconverted
            // amount denominated in the wrong currency, which would over- or under-pay.
            if (address(prices) == address(0)) return (0, convertedMetadata);

            {
                // Get the price ratio: how many payment-currency units per one tier-pricing-currency unit.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 ratio = prices.pricePerUnitOf({
                    projectId: projectId,
                    pricingCurrency: amountCurrency,
                    // forge-lint: disable-next-line(unsafe-typecast)
                    unitCurrency: uint256(uint32(packedPricingContext)),
                    decimals: amountDecimals
                });

                // The denominator scales each amount from tier-pricing decimals to payment-token decimals.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 denom = 10 ** uint256(uint8(packedPricingContext >> 32));

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
        }

        // Cap the total at the actual payment value. Pay credits fund NFT minting (virtual), but splits
        // require real tokens to distribute. Without this cap, a user with sufficient pay credits but
        // insufficient ETH would revert because the terminal can't forward more than what was actually paid.
        if (convertedTotal > amountValue) {
            // Proportionally reduce each per-tier amount to stay in sync with the capped total.
            if (convertedMetadata.length != 0) {
                (uint16[] memory tierIds, uint256[] memory amounts) =
                    abi.decode(convertedMetadata, (uint16[], uint256[]));
                uint256 uncappedTotal = convertedTotal;
                convertedTotal = 0;
                for (uint256 i; i < amounts.length;) {
                    // Scale down: amount * amountValue / originalTotal.
                    amounts[i] = mulDiv({x: amounts[i], y: amountValue, denominator: uncappedTotal});
                    convertedTotal += amounts[i];

                    unchecked {
                        ++i;
                    }
                }
                convertedMetadata = abi.encode(tierIds, amounts);
            } else {
                // Clamp the total to the payment value.
                convertedTotal = amountValue;
            }
        }
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

    /// @notice Pulls ERC-20 tokens from the terminal (if needed) and distributes forwarded funds to tier splits.
    /// @dev For ERC-20 tokens, pulls from the terminal using the allowance it granted via _beforeTransferTo.
    /// @param directory The directory to look up terminals.
    /// @param splits The splits contract to read tier split groups from.
    /// @param projectId The project ID of the hook.
    /// @param hookAddress The hook address (for computing split group IDs).
    /// @param token The token being distributed.
    /// @param amount The total amount to distribute.
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
                revert JB721TiersHookLib_TokenTransferAmountMismatch(amount, receivedAmount);
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
        // slither-disable-next-line calls-loop
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
                // slither-disable-next-line calls-loop,reentrancy-no-eth,reentrancy-benign,reentrancy-events
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
            // slither-disable-next-line calls-loop
            IJBTerminal terminal = directory.primaryTerminalOf({projectId: projectId, token: token});
            // Revert if there are leftover funds but no terminal to route them to.
            if (address(terminal) == address(0)) {
                revert JB721TiersHookLib_NoTerminalForLeftover(projectId, token, leftoverAmount);
            }
            if (isNativeToken) {
                // slither-disable-next-line arbitrary-send-eth,calls-loop
                try terminal.addToBalanceOf{value: leftoverAmount}({
                    projectId: projectId,
                    token: token,
                    amount: leftoverAmount,
                    shouldReturnHeldFees: false,
                    memo: "",
                    metadata: bytes("")
                }) {}
                catch (bytes memory reason) {
                    revert JB721TiersHookLib_SplitFallbackFailed(projectId, token, leftoverAmount, reason);
                }
            } else {
                SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: leftoverAmount});
                // slither-disable-next-line calls-loop
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
                    revert JB721TiersHookLib_SplitFallbackFailed(projectId, token, leftoverAmount, reason);
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
                // slither-disable-next-line calls-loop,reentrancy-no-eth,reentrancy-events
                try split.hook.processSplitWith{value: amount}(context) {
                    return true;
                } catch (bytes memory reason) {
                    // slither-disable-next-line reentrancy-events
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
                // slither-disable-next-line calls-loop,reentrancy-no-eth,reentrancy-events
                try split.hook.processSplitWith(context) {}
                catch (bytes memory reason) {
                    // slither-disable-next-line reentrancy-events
                    emit SplitPayoutReverted({
                        projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                    });
                }
                return true;
            }
        } else if (split.projectId != 0) {
            // slither-disable-next-line calls-loop
            IJBTerminal terminal = directory.primaryTerminalOf({projectId: split.projectId, token: token});
            if (address(terminal) == address(0)) return false;

            // Wrap terminal calls in try-catch to prevent a failing terminal from bricking payments.
            if (split.preferAddToBalance) {
                if (isNativeToken) {
                    // slither-disable-next-line arbitrary-send-eth,calls-loop,reentrancy-no-eth,reentrancy-events
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
                        // slither-disable-next-line reentrancy-events
                        emit SplitPayoutReverted({
                            projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                        });
                        return false;
                    }
                } else {
                    SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: amount});
                    // slither-disable-next-line calls-loop,reentrancy-no-eth,reentrancy-events
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
                        // slither-disable-next-line reentrancy-events
                        emit SplitPayoutReverted({
                            projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                        });
                        return false;
                    }
                }
            } else {
                if (isNativeToken) {
                    // slither-disable-next-line arbitrary-send-eth,unused-return,calls-loop,reentrancy-events
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
                        // slither-disable-next-line reentrancy-events
                        emit SplitPayoutReverted({
                            projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                        });
                        return false;
                    }
                } else {
                    SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: amount});
                    // slither-disable-next-line unused-return,calls-loop,reentrancy-no-eth,reentrancy-events
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
                        // slither-disable-next-line reentrancy-events
                        emit SplitPayoutReverted({
                            projectId: projectId, split: split, amount: amount, reason: reason, caller: msg.sender
                        });
                        return false;
                    }
                }
            }
        } else if (split.beneficiary != address(0)) {
            if (isNativeToken) {
                // slither-disable-next-line arbitrary-send-eth,calls-loop
                (bool success,) = split.beneficiary.call{value: amount}("");
                if (!success) return false;
            } else {
                // Use the same low-level call + returndata check as SafeERC20.safeTransfer, but return
                // false on failure instead of reverting. This handles non-standard tokens (e.g. USDT)
                // that return void, while routing failed transfers to the project's balance instead
                // of bricking all payments.
                // slither-disable-next-line calls-loop
                (bool callSuccess, bytes memory returndata) =
                    address(token).call(abi.encodeCall(IERC20.transfer, (split.beneficiary, amount)));
                if (!callSuccess || (returndata.length != 0 && !abi.decode(returndata, (bool)))) return false;
            }
            return true;
        }
        // No projectId and no beneficiary — return false so the funds go to the project's balance.
        return false;
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
}
