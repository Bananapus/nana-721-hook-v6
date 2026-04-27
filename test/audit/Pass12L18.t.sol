// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

/// @notice L-18: Prevent future tier pre-removal.
/// Removing a tier ID that does not yet exist should revert with `UnrecognizedTier`.
contract Pass12L18 is Test {
    JB721TiersHookStore internal store;

    function setUp() external {
        store = new JB721TiersHookStore();
    }

    /// @notice Removing a future tier ID (beyond maxTierIdOf) must revert.
    function test_L18_fix_reverts_future_removal() external {
        // Add 5 tiers so maxTierIdOf == 5.
        JB721TierConfig[] memory tiers = new JB721TierConfig[](5);
        for (uint256 i; i < 5; i++) {
            tiers[i] = _tier(uint24(i + 1));
        }
        store.recordAddTiers(tiers);
        assertEq(store.maxTierIdOf(address(this)), 5);

        // Attempt to remove tier 10 (future) — should revert.
        uint256[] memory futureTierIds = new uint256[](1);
        futureTierIds[0] = 10;
        vm.expectRevert(abi.encodeWithSignature("JB721TiersHookStore_UnrecognizedTier(uint256)", 10));
        store.recordRemoveTierIds(futureTierIds);

        // Attempt to remove tier 0 (invalid) — should also revert.
        uint256[] memory zeroTierIds = new uint256[](1);
        zeroTierIds[0] = 0;
        vm.expectRevert(abi.encodeWithSignature("JB721TiersHookStore_UnrecognizedTier(uint256)", 0));
        store.recordRemoveTierIds(zeroTierIds);
    }

    /// @notice Removing an existing tier still works as before.
    function test_L18_existing_tier_removal_works() external {
        // Add 5 tiers.
        JB721TierConfig[] memory tiers = new JB721TierConfig[](5);
        for (uint256 i; i < 5; i++) {
            tiers[i] = _tier(uint24(i + 1));
        }
        store.recordAddTiers(tiers);

        // Remove tier 3 — should succeed.
        uint256[] memory removeTierIds = new uint256[](1);
        removeTierIds[0] = 3;
        store.recordRemoveTierIds(removeTierIds);
        assertTrue(store.isTierRemoved({hook: address(this), tierId: 3}));

        // Other tiers should not be affected.
        assertFalse(store.isTierRemoved({hook: address(this), tierId: 1}));
        assertFalse(store.isTierRemoved({hook: address(this), tierId: 2}));
        assertFalse(store.isTierRemoved({hook: address(this), tierId: 4}));
        assertFalse(store.isTierRemoved({hook: address(this), tierId: 5}));
    }

    function _tier(uint24 category) internal pure returns (JB721TierConfig memory tier) {
        tier.price = 1;
        tier.initialSupply = 10;
        tier.category = category;
        tier.flags = JB721TierConfigFlags({
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cantBeRemoved: false,
            cantIncreaseDiscountPercent: false,
            cantBuyWithCredits: false
        });
        tier.splits = new JBSplit[](0);
    }
}
