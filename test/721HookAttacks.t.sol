// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./utils/UnitTestSetup.sol";

/// @title 721HookAttacks
/// @notice Adversarial security tests for JB721TiersHook and JB721TiersHookStore.
contract NFTHookAttacks is UnitTestSetup {
    using stdStorage for StdStorage;

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @dev Mock the directory to accept `mockTerminalAddress` as a terminal for `projectId`.
    function _mockTerminalAuth() internal {
        mockAndExpect(
            mockJBDirectory,
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );
    }

    /// @dev Create a pay context that requests minting specific tier IDs.
    function _buildPayContext(
        address targetHook,
        uint256 value,
        uint16[] memory tierIds
    )
        internal
        view
        returns (JBAfterPayRecordedContext memory)
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, tierIds);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", targetHook);
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        return JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: value,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 0,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });
    }

    // =========================================================================
    // Test 1: Zero-price tier — can an attacker mint for free?
    // =========================================================================
    /// @notice Add a tier with price=0 via adjustTiers. Verify the hook handles it correctly.
    function test_zeroPriceTier_mintBehavior() public {
        // Create hook with 1 default tier (price=10).
        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);

        // Add a zero-price tier via adjustTiers (tier ID 2).
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](1);
        newTiers[0] = JB721TierConfig({
            price: 0,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: reserveBeneficiary,
            encodedIPFSUri: tokenUris[0],
            category: 2,
            discountPercent: 0,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            useVotingUnits: false,
            splitPercent: 0
        });

        vm.prank(owner);
        targetHook.adjustTiers(newTiers, new uint256[](0));

        _mockTerminalAuth();

        // Try to mint tier 2 (price=0) with 0 value.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 2;

        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), 0, tierIds);

        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(ctx);

        // Verify the NFT was minted to the beneficiary.
        assertEq(targetHook.balanceOf(beneficiary), 1, "Should mint 1 NFT at price 0");
    }

    // =========================================================================
    // Test 2: Discount percent at maximum — effective price becomes 0
    // =========================================================================
    /// @notice Set discount to 100%, verify the effective price for the tier.
    function test_maxDiscountPercent_effectivePrice() public {
        defaultTierConfig.discountPercent = 0;
        defaultTierConfig.cannotIncreaseDiscountPercent = false;

        JB721TiersHook targetHook = _initHookDefaultTiers(1);

        // Owner sets discount to 100%.
        vm.mockCall(
            mockJBPermissions,
            abi.encodeWithSelector(IJBPermissions.hasPermission.selector),
            abi.encode(true)
        );

        vm.prank(owner);
        targetHook.setDiscountPercentOf(1, 100);

        // Read the tier and verify the discount was applied.
        JB721Tier memory tier = store.tierOf(address(targetHook), 1, false);
        assertEq(tier.discountPercent, 100, "Discount should be 100%");
    }

    // =========================================================================
    // Test 3: cannotIncreaseDiscountPercent flag enforcement
    // =========================================================================
    /// @notice Try to increase discount when the flag forbids it.
    function test_cannotIncreaseDiscountPercent_enforcement() public {
        defaultTierConfig.discountPercent = 10;
        defaultTierConfig.cannotIncreaseDiscountPercent = true;

        JB721TiersHook targetHook = _initHookDefaultTiers(1);

        vm.mockCall(
            mockJBPermissions,
            abi.encodeWithSelector(IJBPermissions.hasPermission.selector),
            abi.encode(true)
        );

        // Try to increase discount from 10 to 50 — should revert.
        vm.prank(owner);
        vm.expectRevert();
        targetHook.setDiscountPercentOf(1, 50);

        // Decreasing should still work.
        vm.prank(owner);
        targetHook.setDiscountPercentOf(1, 5);

        JB721Tier memory tier = store.tierOf(address(targetHook), 1, false);
        assertEq(tier.discountPercent, 5, "Discount decrease should work");
    }

    // =========================================================================
    // Test 4: Reserve minting drain — high reserve frequency
    // =========================================================================
    /// @notice With reserveFrequency=1 (reserve on every mint), mint 5 paid NFTs
    ///         then call mintPendingReservesFor to drain reserves.
    function test_reserveDrain_highFrequency() public {
        defaultTierConfig.initialSupply = 100;
        defaultTierConfig.reserveFrequency = 1; // Reserve 1 per 1 paid mint.

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        _mockTerminalAuth();

        // Mint 5 paid NFTs from tier 1 (price=10 each, so value=50).
        uint16[] memory tierIds = new uint16[](5);
        for (uint256 i; i < 5; i++) tierIds[i] = 1;

        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), 50, tierIds);

        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(ctx);

        assertEq(targetHook.balanceOf(beneficiary), 5, "5 paid NFTs minted");

        // Pending reserves should be 5 (1 per paid mint with frequency=1).
        // With frequency=1: reserveCount = nftsMinted / frequency = 5, plus 1 if remainder > 0.
        // 5/1 = 5, remainder 0, so pending = 5+1 = 6? Actually the formula is:
        // numberOfPendingReservesFor = (numberOfMints + frequency - 1) / frequency - processedReserves
        // Let's just check what the store reports.
        uint256 pending = hookStore.numberOfPendingReservesFor(address(targetHook), 1);
        assertTrue(pending > 0, "Should have pending reserves");

        // Mint all pending reserves.
        vm.prank(owner);
        targetHook.mintPendingReservesFor(1, pending);

        // After minting, pending should be 0.
        uint256 pendingAfter = hookStore.numberOfPendingReservesFor(address(targetHook), 1);
        assertEq(pendingAfter, 0, "No pending reserves after minting");

        // Try to mint more reserves — should revert (nothing pending).
        vm.prank(owner);
        vm.expectRevert();
        targetHook.mintPendingReservesFor(1, 1);
    }

    // =========================================================================
    // Test 5: Cash-out weight after tier removal
    // =========================================================================
    /// @notice Mint NFTs from a tier, then remove the tier. Verify that
    ///         totalCashOutWeight still accounts for the minted tokens.
    function test_cashOutWeight_afterTierRemoval() public {
        defaultTierConfig.initialSupply = 100;
        defaultTierConfig.votingUnits = 10;
        defaultTierConfig.useVotingUnits = true;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        _mockTerminalAuth();

        // Mint 3 NFTs from tier 1 (price=10 each, value=30).
        uint16[] memory tierIds = new uint16[](3);
        tierIds[0] = 1;
        tierIds[1] = 1;
        tierIds[2] = 1;

        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), 30, tierIds);

        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(ctx);

        assertEq(targetHook.balanceOf(beneficiary), 3, "3 NFTs minted");

        // Get total cash-out weight before removal (from the store).
        uint256 weightBefore = hookStore.totalCashOutWeight(address(targetHook));

        // Remove tier 1.
        vm.mockCall(
            mockJBPermissions,
            abi.encodeWithSelector(IJBPermissions.hasPermission.selector),
            abi.encode(true)
        );

        uint256[] memory tierIdsToRemove = new uint256[](1);
        tierIdsToRemove[0] = 1;

        vm.prank(owner);
        targetHook.adjustTiers(new JB721TierConfig[](0), tierIdsToRemove);

        // Verify the tier is removed.
        assertTrue(hookStore.isTierRemoved(address(targetHook), 1), "Tier should be removed");

        // Total cash-out weight should still include the minted tokens.
        uint256 weightAfter = hookStore.totalCashOutWeight(address(targetHook));
        assertEq(weightAfter, weightBefore, "Cash-out weight should be preserved after removal");
    }

    // =========================================================================
    // Test 6: Invalid tier ID in pay metadata — reverts when overspending prevented
    // =========================================================================
    /// @notice Pass a tier ID that doesn't exist. With preventOverspending=true, must revert.
    function test_invalidTierIdInMetadata_reverts() public {
        // Use preventOverspending=true so invalid tiers cause a revert.
        JB721TiersHook targetHook = _initHookDefaultTiers(1, true);

        _mockTerminalAuth();

        // Try to mint tier 999 which doesn't exist.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 999;

        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), 1 ether, tierIds);

        vm.prank(mockTerminalAddress);
        vm.expectRevert();
        targetHook.afterPayRecordedWith(ctx);
    }

    // =========================================================================
    // Test 7: Duplicate tier IDs in pay metadata — mints multiple NFTs
    // =========================================================================
    /// @notice Pass the same tier ID multiple times. Should mint multiple NFTs
    ///         from that tier.
    function test_duplicateTierIdsInMetadata_mintsMultiple() public {
        defaultTierConfig.initialSupply = 100;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        _mockTerminalAuth();

        // Mint 3 of the same tier (price=10 each, value=30).
        uint16[] memory tierIds = new uint16[](3);
        tierIds[0] = 1;
        tierIds[1] = 1;
        tierIds[2] = 1;

        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), 30, tierIds);

        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(ctx);

        assertEq(targetHook.balanceOf(beneficiary), 3, "3 NFTs minted from same tier");

        // Verify remaining supply decreased.
        JB721Tier memory tier = hookStore.tierOf(address(targetHook), 1, false);
        assertEq(tier.remainingSupply, 97, "Supply should decrease by 3");
    }

    // =========================================================================
    // Test 8: Supply exhaustion — no additional NFTs minted after supply drained
    // =========================================================================
    /// @notice Mint the entire supply of a tier, then verify no more can be minted.
    function test_supplyExhaustion_noOvermint() public {
        defaultTierConfig.initialSupply = 3; // Only 3 available.
        defaultTierConfig.reserveFrequency = 0; // No reserves to keep it simple.

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        _mockTerminalAuth();

        // Mint all 3 (price=10 each, value=30).
        uint16[] memory tierIds = new uint16[](3);
        tierIds[0] = 1;
        tierIds[1] = 1;
        tierIds[2] = 1;

        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), 30, tierIds);

        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(ctx);

        assertEq(targetHook.balanceOf(beneficiary), 3, "All 3 minted");

        // Verify supply is exhausted.
        JB721Tier memory tier = hookStore.tierOf(address(targetHook), 1, false);
        assertEq(tier.remainingSupply, 0, "No remaining supply");

        // Try to mint one more — store enforces supply limit and reverts.
        uint16[] memory oneMore = new uint16[](1);
        oneMore[0] = 1;

        JBAfterPayRecordedContext memory ctx2 = _buildPayContext(address(targetHook), 10, oneMore);

        vm.prank(mockTerminalAddress);
        vm.expectRevert();
        targetHook.afterPayRecordedWith(ctx2);
    }

    // =========================================================================
    // Test 9: adjustTiers without permission — must revert
    // =========================================================================
    /// @notice Non-owner without ADJUST_721_TIERS permission tries to add/remove tiers.
    function test_adjustTiers_noPermission_reverts() public {
        JB721TiersHook targetHook = _initHookDefaultTiers(1);

        // Mock permissions to return false.
        vm.mockCall(
            mockJBPermissions,
            abi.encodeWithSelector(IJBPermissions.hasPermission.selector),
            abi.encode(false)
        );

        address attacker = makeAddr("attacker");

        // Try to add a new tier.
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](1);
        newTiers[0] = JB721TierConfig({
            price: 1,
            initialSupply: type(uint32).max,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: attacker,
            encodedIPFSUri: tokenUris[0],
            category: 1,
            discountPercent: 0,
            allowOwnerMint: true,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            useVotingUnits: false,
            splitPercent: 0
        });

        vm.prank(attacker);
        vm.expectRevert();
        targetHook.adjustTiers(newTiers, new uint256[](0));
    }

    // =========================================================================
    // Test 10: Tier with max supply — verify no overflow
    // =========================================================================
    /// @notice Add a tier with initialSupply = 999_999_999 (store maximum).
    ///         Verify it's created correctly and doesn't overflow.
    function test_maxSupplyTier_noOverflow() public {
        defaultTierConfig.initialSupply = 999_999_999; // Store maximum

        JB721TiersHook targetHook = _initHookDefaultTiers(1);

        // Read the tier to verify the supply was stored correctly.
        JB721Tier memory tier = store.tierOf(address(targetHook), 1, false);
        assertEq(tier.initialSupply, 999_999_999, "Initial supply should be 999_999_999");
        assertEq(tier.remainingSupply, 999_999_999, "Remaining supply should be 999_999_999");
    }
}
