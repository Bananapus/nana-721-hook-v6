// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../utils/UnitTestSetup.sol";

import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";
import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

contract RepoFindings is UnitTestSetup {
    address payable internal splitBeneficiary = payable(makeAddr("splitBeneficiary"));

    function _payMetadata(
        address hookAddress,
        bool allowOverspending,
        uint16[] memory tierIds
    )
        internal
        view
        returns (bytes memory)
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIds);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", hookAddress);
        return metadataHelper.createMetadata(ids, data);
    }

    function _nativeTokenAmount(uint256 value) internal pure returns (JBTokenAmount memory) {
        return JBTokenAmount({
            token: JBConstants.NATIVE_TOKEN,
            value: value,
            decimals: 18,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
    }

    function test_payCredits_can_underfund_split_bearing_tier_mints() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);

        vm.mockCall(mockJBSplits, abi.encodeWithSelector(IJBSplits.setSplitGroupsOf.selector), abi.encode());

        JBSplit[] memory tierSplits = new JBSplit[](1);
        tierSplits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: splitBeneficiary,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: 1 ether,
            initialSupply: 10,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32(uint256(0x1234)),
            category: 1,
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
            splitPercent: JBConstants.SPLITS_TOTAL_PERCENT,
            splits: tierSplits
        });

        vm.prank(owner);
        testHook.adjustTiers(tierConfigs, new uint256[](0));

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(1) << 160);
        vm.mockCall(
            mockJBSplits,
            abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, uint256(0), groupId),
            abi.encode(tierSplits)
        );

        mockAndExpect(
            mockJBDirectory,
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: _nativeTokenAmount(1 ether),
                forwardedAmount: _nativeTokenAmount(0),
                weight: 10e18,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: bytes(""),
                payerMetadata: bytes("")
            })
        );

        assertEq(testHook.payCreditsOf(beneficiary), 1 ether, "setup: credits should be seeded");

        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;
        bytes memory payerMetadata = _payMetadata(address(testHook), true, tierIdsToMint);

        JBBeforePayRecordedContext memory beforeContext = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: _nativeTokenAmount(1),
            projectId: projectId,
            rulesetId: 0,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: payerMetadata
        });

        (uint256 weight, JBPayHookSpecification[] memory specs) = testHook.beforePayRecordedWith(beforeContext);

        assertEq(weight, 0, "only the fresh 1 wei payment is considered for split weight adjustment");
        assertEq(specs.length, 1);
        assertEq(specs[0].amount, 1, "split forwarding is capped to the fresh payment, not the credit-backed mint");

        uint256 splitBeneficiaryBalanceBefore = splitBeneficiary.balance;
        vm.deal(mockTerminalAddress, 1);

        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 1}(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: _nativeTokenAmount(1),
                forwardedAmount: _nativeTokenAmount(1),
                weight: weight,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: specs[0].metadata,
                payerMetadata: payerMetadata
            })
        );

        assertEq(testHook.balanceOf(beneficiary), 1, "beneficiary still receives the split-bearing NFT");
        assertEq(testHook.payCreditsOf(beneficiary), 1, "stored credits fund essentially the entire mint");
        assertEq(
            splitBeneficiary.balance - splitBeneficiaryBalanceBefore,
            1,
            "split beneficiary only receives the fresh 1 wei payment instead of the tier's 1 ether split amount"
        );
    }

    /// @notice Creating a tier with reserveFrequency > 0 and no beneficiary (tier-specific or default)
    /// is now rejected at creation time, preventing the retroactive dilution bug.
    function test_new_default_reserve_beneficiary_retroactively_dilutes_existing_tiers() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);

        JB721TierConfig[] memory initialTier = new JB721TierConfig[](1);
        initialTier[0] = JB721TierConfig({
            price: 1 ether,
            initialSupply: 10,
            votingUnits: 0,
            reserveFrequency: 2,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32(uint256(0x1111)),
            category: 1,
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
