// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {JB721Tier} from "../../src/structs/JB721Tier.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

contract RegressionReserveSellout is Test {
    JB721TiersHookStore internal store;

    function setUp() public {
        store = new JB721TiersHookStore();
    }

    /// @notice Verifies that a paid mint cannot consume the last slot when it is reserved.
    /// @dev Previously this test demonstrated the bug (paid mint succeeded). Now it confirms the fix.
    function test_paidMintCannotConsumeReservedFinalSlot() public {
        JB721TierConfig[] memory tiers = new JB721TierConfig[](1);
        tiers[0] = JB721TierConfig({
            price: 1 ether,
            initialSupply: 2,
            votingUnits: 0,
            reserveFrequency: 1,
            reserveBeneficiary: address(0xBEEF),
            encodedIPFSUri: bytes32(0),
            category: 0,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        store.recordAddTiers(tiers);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        store.recordMint({amount: 1 ether, tierIds: tierIds, isOwnerMint: false});

        JB721Tier memory tier = store.tierOf(address(this), 1, false);
        assertEq(tier.remainingSupply, 1, "one paid mint leaves one slot");
        assertEq(store.numberOfPendingReservesFor(address(this), 1), 1, "one reserve is pending");

        // With the fix, the second paid mint reverts because the remaining slot is reserved.
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector, 1)
        );
        store.recordMint({amount: 1 ether, tierIds: tierIds, isOwnerMint: false});

        // Reserve beneficiary can still claim their entitled mint.
        store.recordMintReservesFor({tierId: 1, count: 1});
        assertEq(store.numberOfReservesMintedFor(address(this), 1), 1, "reserve beneficiary got their token");
    }
}
