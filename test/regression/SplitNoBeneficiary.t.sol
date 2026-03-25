// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
// forge-lint: disable-next-line(unused-import)
import {JB721TiersHookLib} from "../../src/libraries/JB721TiersHookLib.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";

/// @notice Split with no beneficiary and no projectId should route funds to the project's
/// balance instead of silently dropping them.
contract Test_L36_SplitNoBeneficiary is UnitTestSetup {
    using stdStorage for StdStorage;

    address mockProjectTerminal = makeAddr("mockProjectTerminal");

    function setUp() public override {
        super.setUp();
        vm.etch(mockJBSplits, new bytes(0x69));
        vm.etch(mockProjectTerminal, new bytes(0x69));
    }

    /// @notice Verify that a split with projectId==0 and beneficiary==address(0) routes funds to the project's
    /// balance.
    function test_splitWithNoBeneficiary_routesToProjectBalance() public {
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
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        // Mock the project's primary terminal for addToBalanceOf (this is the fallback for no-recipient splits).
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, projectId, JBConstants.NATIVE_TOKEN),
            abi.encode(mockProjectTerminal)
        );

        // Expect addToBalanceOf to be called on the project's terminal with the split amount (0.5 ether).
        vm.expectCall(
            mockProjectTerminal,
            0.5 ether,
            abi.encodeWithSelector(
                IJBTerminal.addToBalanceOf.selector, projectId, JBConstants.NATIVE_TOKEN, 0.5 ether, false, "", ""
            )
        );
        // Mock the addToBalanceOf call to succeed.
        vm.mockCall(mockProjectTerminal, abi.encodeWithSelector(IJBTerminal.addToBalanceOf.selector), abi.encode());

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
        // Should NOT revert — funds should be routed to the project's balance.
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
