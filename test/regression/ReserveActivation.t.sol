// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {JB721Tier} from "../../src/structs/JB721Tier.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

contract Test_ReserveActivation is Test {
    JB721TiersHookStore internal store;

    function setUp() external {
        store = new JB721TiersHookStore();
    }

    /// @notice Creating a tier with reserveFrequency > 0 and no beneficiary (tier-specific or default)
    /// is now rejected at creation time. This prevents the phantom-reserves scenario entirely.
    function test_soldOutTier_noPhantomReserves_afterDefaultBeneficiaryChange() external {
        // Attempt to add a tier with reserve frequency but no beneficiary — should revert.
        JB721TierConfig[] memory initialTiers = new JB721TierConfig[](1);
        initialTiers[0] = _tier({
            price: 1,
            initialSupply: 10,
            reserveFrequency: 2,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            category: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_MissingReserveBeneficiary.selector, 1)
        );
        store.recordAddTiers(initialTiers);
    }

    /// @notice Creating a tier with reserveFrequency > 0 and no beneficiary (tier-specific or default)
    /// is now rejected at creation time. This prevents the retroactive reserve activation scenario entirely.
    function test_nonSoldOutTier_reservesStillWork_afterDefaultBeneficiaryChange() external {
        // Attempt to add a tier with reserve frequency but no beneficiary — should revert.
        JB721TierConfig[] memory initialTiers = new JB721TierConfig[](1);
        initialTiers[0] = _tier({
            price: 1,
            initialSupply: 100,
            reserveFrequency: 5,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            category: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_MissingReserveBeneficiary.selector, 1)
        );
        store.recordAddTiers(initialTiers);
    }

    function _tier(
        uint104 price,
        uint32 initialSupply,
        uint16 reserveFrequency,
        address reserveBeneficiary,
        bool useReserveBeneficiaryAsDefault,
        uint24 category
    )
        internal
        pure
        returns (JB721TierConfig memory tier)
    {
        tier.price = price;
        tier.initialSupply = initialSupply;
        tier.reserveFrequency = reserveFrequency;
        tier.reserveBeneficiary = reserveBeneficiary;
        tier.category = category;
        tier.flags = JB721TierConfigFlags({
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: useReserveBeneficiaryAsDefault,
            transfersPausable: false,
            useVotingUnits: false,
            cantBeRemoved: false,
            cantIncreaseDiscountPercent: false,
            cantBuyWithCredits: false
        });
        tier.splits = new JBSplit[](0);
    }
}
