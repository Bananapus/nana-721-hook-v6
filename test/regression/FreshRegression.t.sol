// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UnitTestSetup} from "../utils/UnitTestSetup.sol";
import {ForTest_JB721TiersHook} from "../utils/ForTest_JB721TiersHook.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core-v6/src/structs/JBBeforePayRecordedContext.sol";
import {JBAfterPayRecordedContext} from "@bananapus/core-v6/src/structs/JBAfterPayRecordedContext.sol";
import {JBPayHookSpecification} from "@bananapus/core-v6/src/structs/JBPayHookSpecification.sol";
import {JBTokenAmount} from "@bananapus/core-v6/src/structs/JBTokenAmount.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";

contract FreshRegression is UnitTestSetup {
    function _buildPayMetadata(
        address hookAddress,
        bool allowOverspending,
        uint16[] memory tierIdsToMint
    )
        internal
        view
        returns (bytes memory)
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", hookAddress);

        return metadataHelper.createMetadata(ids, data);
    }

    function _nativeAmount(uint256 value) internal pure returns (JBTokenAmount memory) {
        return JBTokenAmount({
            token: JBConstants.NATIVE_TOKEN,
            value: value,
            decimals: 18,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
    }

    function test_payCredits_can_underfund_split_bearing_tier_mints() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();
        address splitReceiver = makeAddr("splitReceiver");

        JB721TierConfig[] memory tiersToAdd = new JB721TierConfig[](1);
        tiersToAdd[0] = JB721TierConfig({
            price: uint104(1 ether),
            initialSupply: uint32(10),
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32(uint256(1)),
            category: uint24(1),
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            splits: new JBSplit[](0)
        });

        vm.prank(owner);
        testHook.adjustTiers(tiersToAdd, new uint256[](0));

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(splitReceiver),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(1) << 160);
        vm.mockCall(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );
        vm.mockCall(
            mockJBDirectory,
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        JBAfterPayRecordedContext memory seedCredits = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: _nativeAmount(1 ether),
            forwardedAmount: _nativeAmount(0),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: bytes("")
        });

        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith(seedCredits);
        assertEq(testHook.payCreditsOf(beneficiary), 1 ether, "setup: credits should be seeded");

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory payerMetadata = _buildPayMetadata(address(testHook), true, tierIds);

        JBBeforePayRecordedContext memory beforeContext = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: _nativeAmount(1),
            projectId: projectId,
            rulesetId: 0,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 0,
            metadata: payerMetadata
        });

        (uint256 weight, JBPayHookSpecification[] memory hookSpecifications) =
            testHook.beforePayRecordedWith(beforeContext);

        assertEq(weight, 0, "all fresh payment value is treated as split-routed");
        assertEq(hookSpecifications.length, 1, "expected single pay hook spec");
        assertEq(hookSpecifications[0].amount, 1, "split forwarding is capped to the fresh payment only");

        JBAfterPayRecordedContext memory mintWithCredits = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: _nativeAmount(1),
            forwardedAmount: _nativeAmount(hookSpecifications[0].amount),
            weight: weight,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: hookSpecifications[0].metadata,
            payerMetadata: payerMetadata
        });

        vm.deal(mockTerminalAddress, 1);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 1}(mintWithCredits);

        assertEq(testHook.balanceOf(beneficiary), 1, "beneficiary still mints the split-bearing NFT");
        assertEq(testHook.payCreditsOf(beneficiary), 1, "stored credits fund essentially the entire mint");
        assertEq(splitReceiver.balance, 1, "split receiver only receives the fresh 1 wei payment");
        assertEq(hookStore.totalCashOutWeight(address(testHook)), 1 ether, "full-price NFT still enters cash-out math");
    }

    /// @notice Creating a tier with reserveFrequency > 0 and no beneficiary (tier-specific or default)
    /// is now rejected at creation time, preventing the retroactive dilution bug.
    function test_new_default_reserve_beneficiary_retroactively_dilutes_existing_tiers() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);

        JB721TierConfig[] memory initialTier = new JB721TierConfig[](1);
        initialTier[0] = JB721TierConfig({
            price: uint104(1 ether),
            initialSupply: uint32(5),
            votingUnits: 0,
            reserveFrequency: uint16(2),
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32(uint256(2)),
            category: uint24(1),
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        // The new creation-time check prevents tiers with reserves but no beneficiary.
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_MissingReserveBeneficiary.selector, 1)
        );
        vm.prank(owner);
        testHook.adjustTiers(initialTier, new uint256[](0));
    }
}
