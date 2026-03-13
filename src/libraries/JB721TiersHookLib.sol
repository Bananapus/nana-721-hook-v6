// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

import {JBSplitGroup} from "@bananapus/core-v6/src/structs/JBSplitGroup.sol";

import {IJB721TiersHookStore} from "../interfaces/IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "../interfaces/IJB721TokenUriResolver.sol";
import {JB721Tier} from "../structs/JB721Tier.sol";
import {JB721TierConfig} from "../structs/JB721TierConfig.sol";
import {JBIpfsDecoder} from "./JBIpfsDecoder.sol";

/// @notice External library for JB721TiersHook operations extracted to stay within the EIP-170 contract size limit.
/// @dev Handles tier adjustments, split calculations, price normalization, and split fund distribution.
library JB721TiersHookLib {
    // Events mirrored from IJB721TiersHook (emitted via DELEGATECALL from the hook's context).
    event AddTier(uint256 indexed tierId, JB721TierConfig tier, address caller);
    event RemoveTier(uint256 indexed tierId, address caller);

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
            for (uint256 i; i < tierIdsToRemove.length; i++) {
                emit RemoveTier({tierId: tierIdsToRemove[i], caller: caller});
            }
            // slither-disable-next-line reentrancy-events
            store.recordRemoveTierIds(tierIdsToRemove);
        }

        // Add tiers.
        if (tiersToAdd.length != 0) {
            uint256[] memory tierIdsAdded = store.recordAddTiers(tiersToAdd);

            // slither-disable-next-line reentrancy-events
            for (uint256 i; i < tiersToAdd.length; i++) {
                emit AddTier({tierId: tierIdsAdded[i], tier: tiersToAdd[i], caller: caller});
            }

            // Set split groups for tiers that have splits configured.
            _setSplitGroupsFor(splits, projectId, hookAddress, tiersToAdd, tierIdsAdded);
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

        // slither-disable-next-line reentrancy-events
        for (uint256 i; i < tiersToAdd.length; i++) {
            emit AddTier({tierId: tierIdsAdded[i], tier: tiersToAdd[i], caller: caller});
        }

        // Set split groups for tiers that have splits configured.
        _setSplitGroupsFor(splits, projectId, hookAddress, tiersToAdd, tierIdsAdded);
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
        uint256 pricingCurrency = uint256(uint32(packedPricingContext));
        if (amountCurrency == pricingCurrency) return (amountValue, true);

        if (address(prices) == address(0)) return (0, false);

        uint256 pricingDecimals = uint256(uint8(packedPricingContext >> 32));
        value = mulDiv(
            amountValue,
            10 ** pricingDecimals,
            prices.pricePerUnitOf({
                projectId: projectId,
                pricingCurrency: amountCurrency,
                unitCurrency: pricingCurrency,
                decimals: amountDecimals
            })
        );
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
        bytes memory data;
        {
            bool found;
            (found, data) = JBMetadataResolver.getDataFor(JBMetadataResolver.getId("pay", metadataIdTarget), metadata);
            if (!found) return (0, bytes(""));
        }

        (, uint16[] memory tierIdsToMint) = abi.decode(data, (bool, uint16[]));
        if (tierIdsToMint.length == 0) return (0, bytes(""));

        uint16[] memory splitTierIds = new uint16[](tierIdsToMint.length);
        uint256[] memory splitAmounts = new uint256[](tierIdsToMint.length);
        uint256 splitTierCount;

        for (uint256 i; i < tierIdsToMint.length; i++) {
            // slither-disable-next-line calls-loop
            JB721Tier memory tier = store.tierOf(hook, tierIdsToMint[i], false);
            if (tier.splitPercent != 0) {
                splitTierIds[splitTierCount] = tierIdsToMint[i];
                splitAmounts[splitTierCount] = mulDiv(tier.price, tier.splitPercent, JBConstants.SPLITS_TOTAL_PERCENT);
                totalSplitAmount += splitAmounts[splitTierCount];
                splitTierCount++;
            }
        }

        if (splitTierCount != 0) {
            assembly {
                mstore(splitTierIds, splitTierCount)
                mstore(splitAmounts, splitTierCount)
            }
            hookMetadata = abi.encode(splitTierIds, splitAmounts);
        }
    }

    /// @notice Converts split amounts from tier pricing denomination to payment token denomination.
    /// @dev Called after `calculateSplitAmounts` when the payment currency differs from the tier pricing currency.
    /// @param totalSplitAmount The total split amount in tier pricing denomination.
    /// @param splitMetadata The encoded per-tier breakdown (tierIds, amounts) from calculateSplitAmounts.
    /// @param packedPricingContext The packed pricing context (currency, decimals).
    /// @param prices The prices contract used for currency conversion.
    /// @param projectId The project ID.
    /// @param amountCurrency The payment amount currency.
    /// @param amountDecimals The payment amount decimals.
    /// @return convertedTotal The total split amount converted to payment token denomination.
    /// @return convertedMetadata The re-encoded per-tier breakdown with converted amounts.
    function convertSplitAmounts(
        uint256 totalSplitAmount,
        bytes memory splitMetadata,
        uint256 packedPricingContext,
        IJBPrices prices,
        uint256 projectId,
        uint256 amountCurrency,
        uint256 amountDecimals
    )
        external
        view
        returns (uint256 convertedTotal, bytes memory convertedMetadata)
    {
        uint256 pricingCurrency = uint256(uint32(packedPricingContext));
        if (amountCurrency == pricingCurrency) return (totalSplitAmount, splitMetadata);

        if (address(prices) == address(0)) return (totalSplitAmount, splitMetadata);

        uint256 pricingDecimals = uint256(uint8(packedPricingContext >> 32));
        uint256 ratio = prices.pricePerUnitOf({
            projectId: projectId,
            pricingCurrency: amountCurrency,
            unitCurrency: pricingCurrency,
            decimals: amountDecimals
        });

        (uint16[] memory tierIds, uint256[] memory amounts) = abi.decode(splitMetadata, (uint16[], uint256[]));
        for (uint256 i; i < amounts.length; i++) {
            amounts[i] = mulDiv(amounts[i], ratio, 10 ** pricingDecimals);
            convertedTotal += amounts[i];
        }
        convertedMetadata = abi.encode(tierIds, amounts);
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
        for (uint256 i; i < tiersToAdd.length; i++) {
            if (tiersToAdd[i].splits.length != 0) splitGroupCount++;
        }
        if (splitGroupCount == 0) return;

        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](splitGroupCount);
        uint256 groupIndex;
        for (uint256 i; i < tiersToAdd.length; i++) {
            if (tiersToAdd[i].splits.length != 0) {
                splitGroups[groupIndex] = JBSplitGroup({
                    groupId: uint256(uint160(hookAddress)) | (tierIdsAdded[i] << 160), splits: tiersToAdd[i].splits
                });
                groupIndex++;
            }
        }
        splits.setSplitGroupsOf(projectId, 0, splitGroups);
    }

    /// @notice Distributes forwarded funds for all tiers in the hook metadata.
    /// @param directory The directory to look up terminals.
    /// @param splits The splits contract to read tier split groups from.
    /// @param projectId The project ID of the hook.
    /// @param hookAddress The hook address (for computing split group IDs).
    /// @param token The token being distributed.
    /// @param encodedSplitData The encoded per-tier breakdown from hookMetadata.
    function distributeAll(
        IJBDirectory directory,
        IJBSplits splits,
        uint256 projectId,
        address hookAddress,
        address token,
        bytes calldata encodedSplitData
    )
        external
    {
        (uint16[] memory tierIds, uint256[] memory amounts) = abi.decode(encodedSplitData, (uint16[], uint256[]));

        for (uint256 i; i < tierIds.length; i++) {
            if (amounts[i] == 0) continue;
            uint256 groupId = uint256(uint160(hookAddress)) | (uint256(tierIds[i]) << 160);
            _distributeSingleSplit(directory, splits, projectId, token, groupId, amounts[i]);
        }
    }

    /// @notice Distributes funds for a single tier's split group.
    function _distributeSingleSplit(
        IJBDirectory directory,
        IJBSplits splitsContract,
        uint256 projectId,
        address token,
        uint256 groupId,
        uint256 amount
    )
        private
    {
        // slither-disable-next-line calls-loop
        JBSplit[] memory tierSplits = splitsContract.splitsOf(projectId, 0, groupId);

        bool isNativeToken = token == JBConstants.NATIVE_TOKEN;
        uint256 leftoverPercentage = JBConstants.SPLITS_TOTAL_PERCENT;
        uint256 leftoverAmount = amount;

        for (uint256 j; j < tierSplits.length; j++) {
            uint256 payoutAmount = mulDiv(amount, tierSplits[j].percent, leftoverPercentage);
            if (payoutAmount != 0) {
                // Only subtract from leftover if the split has a valid recipient.
                // Splits with no projectId and no beneficiary are skipped — their share
                // stays in leftoverAmount and is added to the project's balance below.
                if (_sendPayoutToSplit(directory, tierSplits[j], token, payoutAmount, isNativeToken)) {
                    unchecked {
                        leftoverAmount -= payoutAmount;
                    }
                }
            }
            unchecked {
                leftoverPercentage -= tierSplits[j].percent;
            }
        }

        if (leftoverAmount != 0) {
            _addToBalance(directory, projectId, token, leftoverAmount, isNativeToken);
        }
    }

    /// @notice Sends a payout to a split recipient.
    /// @return sent Whether the funds were actually sent. Returns false if the split has no valid recipient
    /// (no projectId and no beneficiary), so the caller can route the funds elsewhere.
    function _sendPayoutToSplit(
        IJBDirectory directory,
        JBSplit memory split,
        address token,
        uint256 amount,
        bool isNativeToken
    )
        private
        returns (bool sent)
    {
        if (split.projectId != 0) {
            // slither-disable-next-line calls-loop
            IJBTerminal terminal = directory.primaryTerminalOf(split.projectId, token);
            if (address(terminal) == address(0)) return false;

            if (split.preferAddToBalance) {
                _terminalAddToBalance(terminal, split.projectId, token, amount, isNativeToken);
            } else {
                _terminalPay(terminal, split.projectId, token, amount, split.beneficiary, isNativeToken);
            }
            return true;
        } else if (split.beneficiary != address(0)) {
            if (isNativeToken) {
                // slither-disable-next-line arbitrary-send-eth,calls-loop
                (bool success,) = split.beneficiary.call{value: amount}("");
                if (!success) revert();
            } else {
                SafeERC20.safeTransfer(IERC20(token), split.beneficiary, amount);
            }
            return true;
        }
        // No projectId and no beneficiary — return false so the funds go to the project's balance.
        return false;
    }

    function _addToBalance(
        IJBDirectory directory,
        uint256 projectId,
        address token,
        uint256 amount,
        bool isNativeToken
    )
        private
    {
        // slither-disable-next-line calls-loop
        IJBTerminal terminal = directory.primaryTerminalOf(projectId, token);
        if (address(terminal) == address(0)) return;
        _terminalAddToBalance(terminal, projectId, token, amount, isNativeToken);
    }

    function _terminalAddToBalance(
        IJBTerminal terminal,
        uint256 projectId,
        address token,
        uint256 amount,
        bool isNativeToken
    )
        private
    {
        if (isNativeToken) {
            // slither-disable-next-line arbitrary-send-eth,calls-loop
            terminal.addToBalanceOf{value: amount}(projectId, token, amount, false, "", bytes(""));
        } else {
            SafeERC20.forceApprove(IERC20(token), address(terminal), amount);
            // slither-disable-next-line calls-loop
            terminal.addToBalanceOf(projectId, token, amount, false, "", bytes(""));
        }
    }

    function _terminalPay(
        IJBTerminal terminal,
        uint256 projectId,
        address token,
        uint256 amount,
        address beneficiary,
        bool isNativeToken
    )
        private
    {
        if (isNativeToken) {
            // slither-disable-next-line arbitrary-send-eth,unused-return,calls-loop
            terminal.pay{value: amount}(projectId, token, amount, beneficiary, 0, "", bytes(""));
        } else {
            SafeERC20.forceApprove(IERC20(token), address(terminal), amount);
            // slither-disable-next-line unused-return,calls-loop
            terminal.pay(projectId, token, amount, beneficiary, 0, "", bytes(""));
        }
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
