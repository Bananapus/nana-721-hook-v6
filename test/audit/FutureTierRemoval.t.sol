// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

contract Test_FutureTierRemoval is Test {
    JB721TiersHookStore internal store;

    function setUp() external {
        store = new JB721TiersHookStore();
    }

    function test_futureRemovedTierIdIsBornRemovedAndCannotMint() external {
        JB721TierConfig[] memory firstTier = new JB721TierConfig[](1);
        firstTier[0] = _tier(1);
        uint256[] memory firstIds = store.recordAddTiers(firstTier);
        assertEq(firstIds[0], 1);

        uint256[] memory futureIds = new uint256[](1);
        futureIds[0] = 2;
        store.recordRemoveTierIds(futureIds);
        assertTrue(store.isTierRemoved({hook: address(this), tierId: 2}));

        JB721TierConfig[] memory secondTier = new JB721TierConfig[](1);
        secondTier[0] = _tier(2);
        uint256[] memory secondIds = store.recordAddTiers(secondTier);
        assertEq(secondIds[0], 2);
        assertTrue(store.isTierRemoved({hook: address(this), tierId: 2}));

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 2;
        vm.expectRevert(abi.encodeWithSignature("JB721TiersHookStore_TierRemoved(uint256)", 2));
        store.recordMint({amount: 1, tierIds: tierIds, isOwnerMint: false});
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
