// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

contract Test_20260425CodexNemesisFutureTierRemoval is Test {
    JB721TiersHookStore internal store;

    function setUp() external {
        store = new JB721TiersHookStore();
    }

    function test_futureRemovedTierIdIsBornRemovedAndCannotMint() external {
        JB721TierConfig[] memory firstTier = new JB721TierConfig[](1);
        firstTier[0] = _tier(1);
        uint256[] memory firstIds = store.recordAddTiers(firstTier);
        assertEq(firstIds[0], 1);

        // Attempting to remove a future (nonexistent) tier ID should now revert
        // thanks to the L-18 fix, preventing the "born removed" bug.
        uint256[] memory futureIds = new uint256[](1);
        futureIds[0] = 2;
        vm.expectRevert(abi.encodeWithSignature("JB721TiersHookStore_UnrecognizedTier(uint256)", 2));
        store.recordRemoveTierIds(futureIds);
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
