// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {JB721Tier} from "../../src/structs/JB721Tier.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

contract Test_20260425CodexNemesisReserveActivation is Test {
    JB721TiersHookStore internal store;

    function setUp() external {
        store = new JB721TiersHookStore();
    }

    function test_retroactiveDefaultReserveBeneficiaryCreatesUnmintablePendingReserves() external {
        JB721TierConfig[] memory initialTiers = new JB721TierConfig[](1);
        initialTiers[0] = _tier({
            price: 1,
            initialSupply: 10,
            reserveFrequency: 2,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            category: 1
        });
        store.recordAddTiers(initialTiers);

        uint16[] memory tierIds = new uint16[](10);
        for (uint256 i; i < tierIds.length; i++) {
            tierIds[i] = 1;
        }
        store.recordMint({amount: 10, tierIds: tierIds, isOwnerMint: false});

        JB721Tier memory beforeDefault = store.tierOf({hook: address(this), id: 1, includeResolvedUri: false});
        assertEq(beforeDefault.remainingSupply, 0);
        assertEq(beforeDefault.reserveFrequency, 0);
        assertEq(store.numberOfPendingReservesFor({hook: address(this), tierId: 1}), 0);
        assertEq(store.totalCashOutWeight(address(this)), 10);

        JB721TierConfig[] memory laterTiers = new JB721TierConfig[](1);
        laterTiers[0] = _tier({
            price: 1,
            initialSupply: 10,
            reserveFrequency: 2,
            reserveBeneficiary: address(0xBEEF),
            useReserveBeneficiaryAsDefault: true,
            category: 2
        });
        store.recordAddTiers(laterTiers);

        JB721Tier memory afterDefault = store.tierOf({hook: address(this), id: 1, includeResolvedUri: false});
        assertEq(afterDefault.remainingSupply, 0);
        assertEq(afterDefault.reserveFrequency, 2);
        assertEq(afterDefault.reserveBeneficiary, address(0xBEEF));
        assertEq(store.numberOfPendingReservesFor({hook: address(this), tierId: 1}), 5);
        assertEq(store.totalCashOutWeight(address(this)), 15);

        vm.expectRevert();
        store.recordMintReservesFor({tierId: 1, count: 1});
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
