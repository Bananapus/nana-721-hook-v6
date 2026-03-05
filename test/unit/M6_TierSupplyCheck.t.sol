// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../utils/UnitTestSetup.sol";

/// @title M6_TierSupplyCheck
/// @notice Tests proving the M-6 fix: the supply check must account for pending reserves when minting paid NFTs.
/// Without the `1 +` in the supply check, the last available slot can be consumed by a paid mint, making
/// pending reserves unmintable (recordMintReservesFor reverts decrementing remainingSupply past zero).
contract M6_TierSupplyCheck is UnitTestSetup {
    using stdStorage for StdStorage;

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

    /// @dev Helper: mint `count` NFTs from tier 1 via pay.
    function _mintPaid(ForTest_JB721TiersHook targetHook, uint256 count) internal {
        uint16[] memory tierIds = new uint16[](count);
        for (uint256 i; i < count; i++) {
            tierIds[i] = 1;
        }
        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), count * 10, tierIds); // price=10
        // per NFT
        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(ctx);
    }

    // =========================================================================
    // Test 1: Prove the edge case — paid mint would steal reserves' last slot
    // =========================================================================
    /// @notice With reserveFrequency=2 and initialSupply=10:
    /// After 6 paid mints → 4 remaining, 3 pending reserves.
    /// Without the fix, a 7th paid mint would pass (4 > 3) leaving only 3 remaining for 4 pending reserves.
    /// With the fix, the 7th mint decrements first (remaining→3), then checks 3 < ceil(7/2)=4 → reverts.
    function test_M6_paidMintCannotStealReserveSlot() public {
        // Configure: small supply, reserve every 2 mints.
        defaultTierConfig.price = uint104(10);
        defaultTierConfig.initialSupply = uint32(10);
        defaultTierConfig.reserveFrequency = uint16(2);
        defaultTierConfig.reserveBeneficiary = reserveBeneficiary;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);
        _mockTerminalAuth();

        // Mint 6 paid NFTs. State: remaining=4, nonReserveMints=6, pending=ceil(6/2)=3.
        _mintPaid(targetHook, 6);

        JB721Tier memory tier = targetHook.STORE().tierOf(address(targetHook), 1, false);
        assertEq(tier.remainingSupply, 4, "Should have 4 remaining after 6 mints");

        uint256 pending = targetHook.STORE().numberOfPendingReservesFor(address(targetHook), 1);
        assertEq(pending, 3, "Should have 3 pending reserves (ceil(6/2)=3)");

        // The 7th paid mint should revert: remaining(4) <= 1 + pending(3) = 4.
        // Without the fix (just `<=` pending), this would pass since 4 > 3.
        uint16[] memory oneMore = new uint16[](1);
        oneMore[0] = 1;
        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), 10, oneMore);

        vm.prank(mockTerminalAddress);
        vm.expectRevert(JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector);
        targetHook.afterPayRecordedWith(ctx);
    }

    // =========================================================================
    // Test 2: Reserves remain fully mintable after paid mints
    // =========================================================================
    /// @notice After minting paid NFTs up to the allowed limit, all pending reserves should be mintable.
    function test_M6_reservesFullyMintableAfterPaidMints() public {
        defaultTierConfig.price = uint104(10);
        defaultTierConfig.initialSupply = uint32(10);
        defaultTierConfig.reserveFrequency = uint16(2);
        defaultTierConfig.reserveBeneficiary = reserveBeneficiary;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);
        _mockTerminalAuth();

        // Mint 6 paid NFTs (the maximum allowed given the fix).
        _mintPaid(targetHook, 6);

        // Mint all pending reserves — this must succeed.
        uint256 pending = targetHook.STORE().numberOfPendingReservesFor(address(targetHook), 1);
        assertEq(pending, 3, "3 pending reserves");

        vm.prank(owner);
        targetHook.mintPendingReservesFor(1, pending);

        // Verify: reserve beneficiary got the reserves.
        assertEq(targetHook.balanceOf(reserveBeneficiary), pending, "Reserve beneficiary should have all reserves");

        // Verify: remaining supply is 1 (10 - 6 paid - 3 reserves = 1).
        JB721Tier memory tier = targetHook.STORE().tierOf(address(targetHook), 1, false);
        assertEq(tier.remainingSupply, 1, "Should have 1 remaining (10 - 6 - 3)");
    }

    // =========================================================================
    // Test 3: Boundary — reserves exactly fill remaining supply after max paid mints
    // =========================================================================
    /// @notice With reserveFrequency=5, after 16 paid mints of 20 supply:
    /// remaining=4, pending=ceil(16/5)=4. The 17th mint reverts (4 <= 1+4=5).
    /// All 4 pending reserves are still fully mintable.
    function test_M6_noMintWhenRemainingEqualsReserves() public {
        defaultTierConfig.price = uint104(10);
        defaultTierConfig.initialSupply = uint32(20);
        defaultTierConfig.reserveFrequency = uint16(5);
        defaultTierConfig.reserveBeneficiary = reserveBeneficiary;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);
        _mockTerminalAuth();

        // Mint 16 paid NFTs in two batches to stay under gas limits.
        _mintPaid(targetHook, 10);
        _mintPaid(targetHook, 6);

        // State: remaining=4, nonReserveMints=16, pending=ceil(16/5)=4.
        uint256 pending = targetHook.STORE().numberOfPendingReservesFor(address(targetHook), 1);
        assertEq(pending, 4, "Should have 4 pending reserves (ceil(16/5)=4)");

        JB721Tier memory tier = targetHook.STORE().tierOf(address(targetHook), 1, false);
        assertEq(tier.remainingSupply, 4, "Should have 4 remaining");

        // 17th mint: after decrement remaining would be 3, but pending would be ceil(17/5)=4. 3 < 4 → reverts.
        uint16[] memory oneMore = new uint16[](1);
        oneMore[0] = 1;
        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), 10, oneMore);

        vm.prank(mockTerminalAddress);
        vm.expectRevert(JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector);
        targetHook.afterPayRecordedWith(ctx);

        // But reserves should still be fully mintable — remaining(4) covers all pending(4).
        vm.prank(owner);
        targetHook.mintPendingReservesFor(1, pending);
        assertEq(targetHook.balanceOf(reserveBeneficiary), 4, "All reserves fully minted");

        // Final state: 0 remaining.
        tier = targetHook.STORE().tierOf(address(targetHook), 1, false);
        assertEq(tier.remainingSupply, 0, "Fully exhausted");
    }

    // =========================================================================
    // Test 4: No reserves — full supply mintable
    // =========================================================================
    /// @notice Without reserves, all NFTs in a tier should be mintable (no off-by-one).
    function test_M6_noReserves_fullSupplyMintable() public {
        defaultTierConfig.price = uint104(10);
        defaultTierConfig.initialSupply = uint32(5);
        defaultTierConfig.reserveFrequency = uint16(0);
        defaultTierConfig.reserveBeneficiary = address(0);

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);
        _mockTerminalAuth();

        // Mint all 5 — should succeed since no reserves to protect.
        _mintPaid(targetHook, 5);

        JB721Tier memory tier = targetHook.STORE().tierOf(address(targetHook), 1, false);
        assertEq(tier.remainingSupply, 0, "Fully minted");
        assertEq(targetHook.balanceOf(beneficiary), 5, "Beneficiary has all 5");

        // One more should revert (supply exhausted).
        uint16[] memory oneMore = new uint16[](1);
        oneMore[0] = 1;
        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), 10, oneMore);

        vm.prank(mockTerminalAddress);
        vm.expectRevert();
        targetHook.afterPayRecordedWith(ctx);
    }
}
