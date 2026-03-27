// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";

contract CodexNemesis_SplitFailureRedistribution is UnitTestSetup {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function test_failedEarlierSplit_overpaysLaterSplit() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tierConfigs[0].splitPercent = 1_000_000_000;

        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        RevertOnReceive revertingBeneficiary = new RevertOnReceive();

        JBSplit[] memory splits = new JBSplit[](2);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(address(revertingBeneficiary)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });
        splits[1] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2),
            projectId: 0,
            beneficiary: payable(bob),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        bytes memory payerMetadata = _buildPayMetadata(address(testHook), uint16(tierIds[0]));
        bytes memory hookMetadata = abi.encode(_singleTierId(uint16(tierIds[0])), _singleAmount(1 ether));

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
                value: 1 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: hookMetadata,
            payerMetadata: payerMetadata
        });

        uint256 bobBalanceBefore = bob.balance;

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 1 ether}(payContext);

        assertEq(
            bob.balance - bobBalanceBefore,
            1 ether,
            "later split receives the failed split's share instead of only its own allocation"
        );
    }

    function _buildPayMetadata(address hookAddress, uint16 tierId) internal view returns (bytes memory) {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, _singleTierId(tierId));
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", hookAddress);
        return metadataHelper.createMetadata(ids, data);
    }

    function _singleTierId(uint16 tierId) internal pure returns (uint16[] memory tierIds) {
        tierIds = new uint16[](1);
        tierIds[0] = tierId;
    }

    function _singleAmount(uint256 amount) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = amount;
    }
}

contract RevertOnReceive {
    receive() external payable {
        revert("NO_ETH");
    }
}
