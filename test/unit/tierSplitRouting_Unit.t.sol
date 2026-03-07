// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";

contract Test_TierSplitRouting is UnitTestSetup {
    using stdStorage for StdStorage;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address mockSplits = makeAddr("mockSplits");

    function setUp() public override {
        super.setUp();
        vm.etch(mockSplits, new bytes(0x69));
    }

    // Helper: build a tier config with splits.
    function _tierConfigWithSplit(
        uint104 price,
        uint32 splitPercent
    )
        internal
        pure
        returns (JB721TierConfig memory config)
    {
        config.price = price;
        config.initialSupply = uint32(100);
        config.category = uint24(1);
        config.encodedIPFSUri = bytes32(uint256(0x1234));
        config.splitPercent = splitPercent;
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

    // ──────────────────────────────────────────────
    // Test: beforePayRecordedWith calculates split amount
    // ──────────────────────────────────────────────

    function test_beforePayRecorded_calculatesSplitAmount() public {
        // Create hook with a default tier (no splits).
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add a tier with 50% split directly to the hook's store.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 500_000_000); // 50%
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Build payer metadata requesting that tier.
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 1 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: 0,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: payerMetadata
        });

        (uint256 weight, JBPayHookSpecification[] memory specs) = testHook.beforePayRecordedWith(context);

        // Weight unchanged.
        assertEq(weight, 10e18);
        // Hook spec should forward 50% of 1 ETH = 0.5 ETH.
        assertEq(specs.length, 1);
        assertEq(specs[0].amount, 0.5 ether);
    }

    // ──────────────────────────────────────────────
    // Test: no splitPercent means no forwarded amount
    // ──────────────────────────────────────────────

    function test_beforePayRecorded_noSplitPercent_noForwardedAmount() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add a tier with 0% split.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 0);
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 1 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: 0,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: payerMetadata
        });

        (, JBPayHookSpecification[] memory specs) = testHook.beforePayRecordedWith(context);

        // No split amount forwarded.
        assertEq(specs[0].amount, 0);
    }

    // ──────────────────────────────────────────────
    // Test: multiple tiers with different split percents
    // ──────────────────────────────────────────────

    function test_beforePayRecorded_multipleTiersDifferentSplitPercents() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Tier 1: 1 ETH, 30% split. Tier 2: 2 ETH, 100% split.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](2);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 300_000_000);
        tierConfigs[0].category = 1;
        tierConfigs[1] = _tierConfigWithSplit(2 ether, 1_000_000_000);
        tierConfigs[1].category = 2;
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        uint16[] memory mintIds = new uint16[](2);
        mintIds[0] = uint16(tierIds[0]);
        mintIds[1] = uint16(tierIds[1]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 3 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: 0,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: payerMetadata
        });

        (, JBPayHookSpecification[] memory specs) = testHook.beforePayRecordedWith(context);

        // Total split = 1 ETH * 30% + 2 ETH * 100% = 0.3 + 2.0 = 2.3 ETH.
        assertEq(specs[0].amount, 2.3 ether);
    }

    // ──────────────────────────────────────────────
    // Test: afterPayRecordedWith distributes to split beneficiary
    // ──────────────────────────────────────────────

    function test_afterPayRecorded_distributesToBeneficiary() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add a tier with 50% split.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 500_000_000);
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

        // Mock splits: alice gets 100%.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(alice),
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

        uint256 aliceBalanceBefore = alice.balance;

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 0.5 ether}(payContext);

        // Alice should have received 0.5 ETH.
        assertEq(alice.balance - aliceBalanceBefore, 0.5 ether);
        // NFT should have been minted.
        assertEq(testHook.balanceOf(beneficiary), 1);
    }
}
