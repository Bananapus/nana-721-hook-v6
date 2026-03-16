// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
// forge-lint: disable-next-line(unused-import)
import {JB721TiersHookLib} from "../../src/libraries/JB721TiersHookLib.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";

/// @notice Regression tests for split distribution bugs in JB721TiersHookLib.
contract Test_SplitDistributionBugs is UnitTestSetup {
    using stdStorage for StdStorage;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public override {
        super.setUp();
        vm.etch(mockJBSplits, new bytes(0x69));
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

    // ──────────────────────────────────────────────────────────────────────
    // Split underflow DoS: _distributeSingleSplit with 2+ splits
    // ──────────────────────────────────────────────────────────────────────

    /// @notice When two splits each get 50% of a tier's funds, the old code used `amount`
    /// (the original total) in mulDiv for every split. After the first split consumed half
    /// the funds, the second split would compute its payout from the original `amount`,
    /// yielding a value that exceeds `leftoverAmount`. The unchecked subtraction would
    /// underflow, causing a revert (DoS).
    ///
    /// With the fix (using `leftoverAmount` instead of `amount`), the second split
    /// correctly computes its payout from the remaining funds and the distribution succeeds.
    function test_splitDistribution_twoSplits_usesLeftoverAmount_noUnderflow() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add a tier with 100% split, priced at 1 ETH.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tierConfigs[0].splitPercent = 1_000_000_000; // 100%

        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Mock directory checks.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Mock splits: TWO beneficiaries each with 50%.
        JBSplit[] memory splits = new JBSplit[](2);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2), // 50%
            projectId: 0,
            beneficiary: payable(alice),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });
        splits[1] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2), // 50%
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

        // Build payer metadata.
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        // Build hook metadata (per-tier split breakdown).
        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 1 ether; // Full tier price as split amount.

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
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        vm.deal(mockTerminalAddress, 2 ether);
        vm.prank(mockTerminalAddress);
        // This would revert with the old code due to underflow. With the fix it succeeds.
        testHook.afterPayRecordedWith{value: 1 ether}(payContext);

        // Alice and Bob should each receive 0.5 ETH.
        assertEq(alice.balance - aliceBalanceBefore, 0.5 ether, "Alice should receive 0.5 ETH");
        assertEq(bob.balance - bobBalanceBefore, 0.5 ether, "Bob should receive 0.5 ETH");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Split amounts must use discounted tier price, not full price
    // ──────────────────────────────────────────────────────────────────────

    /// @notice When a tier has a discount, `calculateSplitAmounts()` should use the
    /// discounted price (matching what `recordMint` charges), not the full undiscounted
    /// tier price. Without the fix, the split amount would be inflated.
    function test_calculateSplitAmounts_usesDiscountedPrice() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add a tier with 50% discount and 100% split, priced at 1 ETH.
        // discountPercent=100 out of DISCOUNT_DENOMINATOR=200 means a 50% discount.
        // So the effective price should be 0.5 ETH.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tierConfigs[0].splitPercent = 1_000_000_000; // 100%
        tierConfigs[0].discountPercent = 100; // 50% discount (100/200)

        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Build payer metadata requesting that tier.
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        // Call calculateSplitAmounts via beforePayRecordedWith.
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

        // With 50% discount on a 1 ETH tier and 100% split, the split amount should be 0.5 ETH.
        // Without the fix, it would be 1 ETH (using the full undiscounted price).
        assertEq(specs[0].amount, 0.5 ether, "Split amount should use discounted price (0.5 ETH, not 1 ETH)");
    }

    /// @notice Verify the discounted split amount math matches what recordMint charges.
    /// A tier priced at 2 ETH with a 25% discount (discountPercent=50, denominator=200)
    /// has effective price 1.5 ETH. With 50% split, the split amount should be 0.75 ETH.
    function test_calculateSplitAmounts_partialDiscount_partialSplit() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0].price = 2 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tierConfigs[0].splitPercent = 500_000_000; // 50%
        tierConfigs[0].discountPercent = 50; // 25% discount (50/200)

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
                value: 2 ether,
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

        // effectivePrice = 2 ETH - (2 ETH * 50 / 200) = 2 ETH - 0.5 ETH = 1.5 ETH
        // splitAmount = 1.5 ETH * 50% = 0.75 ETH
        assertEq(specs[0].amount, 0.75 ether, "Split amount should be 0.75 ETH with 25% discount and 50% split");
    }

    // ──────────────────────────────────────────────────────────────────────
    // Failed ETH send to split beneficiary should not revert entire payment
    // ──────────────────────────────────────────────────────────────────────

    /// @notice When an ETH send to a split beneficiary fails (e.g., the beneficiary is a
    /// contract that reverts on receive), the old code propagated the revert, causing the
    /// entire payment to fail. With the fix, the failed send returns false, and the funds
    /// are routed to the project's balance instead.
    function test_revertingSplitBeneficiary_routesToProjectBalance() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add a tier with 100% split.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tierConfigs[0].splitPercent = 1_000_000_000; // 100%

        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Mock directory checks.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Deploy a contract that always reverts when receiving ETH.
        RevertOnReceive revertingBeneficiary = new RevertOnReceive();

        // Mock splits: 100% to a beneficiary that reverts on ETH receive.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(revertingBeneficiary)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        // Mock the project's primary terminal for the fallback addToBalance.
        address projectTerminal = makeAddr("projectTerminal");
        vm.etch(projectTerminal, new bytes(0x69));
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, projectId, JBConstants.NATIVE_TOKEN),
            abi.encode(projectTerminal)
        );

        // Expect addToBalanceOf to be called on the project's terminal with the full 1 ETH
        // (since the beneficiary failed, funds route to project balance).
        vm.expectCall(
            projectTerminal,
            1 ether,
            abi.encodeWithSelector(
                IJBTerminal.addToBalanceOf.selector, projectId, JBConstants.NATIVE_TOKEN, 1 ether, false, "", ""
            )
        );
        vm.mockCall(projectTerminal, abi.encodeWithSelector(IJBTerminal.addToBalanceOf.selector), abi.encode());

        // Build payer metadata.
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        // Build hook metadata.
        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 1 ether;

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
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        vm.deal(mockTerminalAddress, 2 ether);
        vm.prank(mockTerminalAddress);
        // With the old code this would revert. With the fix, it succeeds and routes to project balance.
        testHook.afterPayRecordedWith{value: 1 ether}(payContext);

        // Verify the reverting beneficiary received nothing.
        assertEq(address(revertingBeneficiary).balance, 0, "Reverting beneficiary should receive nothing");
    }
}

/// @notice A contract that always reverts when receiving ETH.
contract RevertOnReceive {
    receive() external payable {
        revert("I reject ETH");
    }
}
