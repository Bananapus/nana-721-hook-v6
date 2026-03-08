// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
import {JB721TiersHookLib} from "../../src/libraries/JB721TiersHookLib.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";

/// @notice Regression test for L-36: Silent fund drop when split has no beneficiary and no projectId.
contract Test_L36_SplitNoBeneficiary is UnitTestSetup {
    using stdStorage for StdStorage;

    address mockSplits = makeAddr("mockSplits");

    function setUp() public override {
        super.setUp();
        vm.etch(mockSplits, new bytes(0x69));
    }

    /// @notice Verify that afterPayRecordedWith reverts when a split has projectId==0 and beneficiary==address(0).
    function test_revert_splitWithNoBeneficiaryAndNoProject() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add a tier with 50% split.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tierConfigs[0].splitPercent = 500_000_000; // 50%

        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Mock directory checks.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.controllerOf.selector, projectId),
            abi.encode(mockJBController)
        );
        mockAndExpect(mockJBController, abi.encodeWithSelector(IJBController.SPLITS.selector), abi.encode(mockSplits));

        // Mock splits: a split with projectId==0 and beneficiary==address(0).
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        // Build payer metadata.
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        // Build hook metadata (per-tier split breakdown from beforePayRecordedWith).
        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 0.5 ether;

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 1 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 0.5 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        vm.expectRevert(JB721TiersHookLib.JB721TiersHookLib_SplitHasNoRecipient.selector);
        testHook.afterPayRecordedWith{value: 0.5 ether}(payContext);
    }

    // Helper: build payer metadata for tier IDs.
    function _buildPayerMetadata(
        address hookAddress,
        uint16[] memory tierIdsToMint
    )
        internal
        view
        returns (bytes memory)
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", hookAddress);
        return metadataHelper.createMetadata(ids, data);
    }
}
