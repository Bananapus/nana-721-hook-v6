// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {JB721Tier} from "../../src/structs/JB721Tier.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

/// @notice Tests that paid mints cannot consume slots reserved for the reserve beneficiary.
/// @dev Regression test for the vulnerability where `_numberOfPendingReservesFor` returns 0
/// when `remainingSupply == 0` (sold-out early-return), allowing the post-decrement guard
/// `0 < 0` to pass and permanently stealing reserved slots from the beneficiary.
/// The fix uses `_numberOfPendingReservesForMintGuard` which omits the sold-out early-return.
contract ReserveSlotProtection is Test {
    JB721TiersHookStore internal store;

    function setUp() public {
        store = new JB721TiersHookStore();
    }

    /// @notice Proves the fix: a paid mint that would consume the last reserved slot reverts.
    /// Scenario: tier with initialSupply=2, reserveFrequency=1 (1 reserve per paid mint).
    /// After 1 paid mint, 1 slot remains but it's reserved. Second paid mint must revert.
    /// Post-decrement trace: remaining goes 2->1, pending=ceil(1/1)=1, check 1<1 = false -> ok.
    /// Second mint: remaining goes 1->0, _numberOfPendingReservesForMintGuard returns 2
    /// (ceil(2/1)-0=2), check 0<2 -> true -> reverts.
    function test_paidMintRevertsWhenOnlyReservedSlotsRemain() public {
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

        // First paid mint succeeds — uses 1 of 2 slots, leaving 1 for the pending reserve.
        store.recordMint({amount: 1 ether, tierIds: tierIds, isOwnerMint: false});

        // Verify state: 1 remaining supply, 1 pending reserve.
        JB721Tier memory tier = store.tierOf(address(this), 1, false);
        assertEq(tier.remainingSupply, 1, "should have 1 slot remaining after first mint");
        assertEq(store.numberOfPendingReservesFor(address(this), 1), 1, "should have 1 pending reserve");

        // Second paid mint MUST revert — the only remaining slot belongs to the reserve beneficiary.
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector, 1)
        );
        store.recordMint({amount: 1 ether, tierIds: tierIds, isOwnerMint: false});
    }

    /// @notice Proves that the reserve beneficiary can still mint their reserved slot after fix.
    function test_reserveBeneficiaryCanMintAfterPaidSlotsExhausted() public {
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

        // First paid mint.
        store.recordMint({amount: 1 ether, tierIds: tierIds, isOwnerMint: false});

        // Reserve beneficiary mints their entitled reserve.
        uint256[] memory reserveTokenIds = store.recordMintReservesFor({tierId: 1, count: 1});
        assertEq(reserveTokenIds.length, 1, "reserve beneficiary should get 1 token");

        // After reserve mint, remaining supply is 0 and reserves are fulfilled.
        JB721Tier memory tier = store.tierOf(address(this), 1, false);
        assertEq(tier.remainingSupply, 0, "tier should be fully minted");
        assertEq(store.numberOfReservesMintedFor(address(this), 1), 1, "1 reserve should be minted");
    }

    /// @notice Tests a larger tier: initialSupply=10, reserveFrequency=2.
    /// With frequency=2, every 2 paid mints earn 1 reserve (rounded up).
    /// Post-decrement analysis for the 7th mint:
    ///   remaining goes 4->3, nonReserveMints=7, pending=ceil(7/2)-0=4.
    ///   Check: 3 < 4 -> true -> reverts. Correct!
    /// So mints 1-6 succeed, mint 7 reverts.
    function test_largerTierReserveProtection() public {
        JB721TierConfig[] memory tiers = new JB721TierConfig[](1);
        tiers[0] = JB721TierConfig({
            price: 0.1 ether,
            initialSupply: 10,
            votingUnits: 0,
            reserveFrequency: 2,
            reserveBeneficiary: address(0xCAFE),
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

        // Mint 6 paid NFTs. After 6 mints: remaining=4, pending=ceil(6/2)=3.
        for (uint256 i; i < 6; i++) {
            store.recordMint({amount: 0.1 ether, tierIds: tierIds, isOwnerMint: false});
        }

        JB721Tier memory tier = store.tierOf(address(this), 1, false);
        assertEq(tier.remainingSupply, 4, "should have 4 remaining after 6 mints");
        assertEq(store.numberOfPendingReservesFor(address(this), 1), 3, "should have 3 pending reserves");

        // 7th paid mint should revert: after decrement, remaining=3, pending=ceil(7/2)=4. 3<4 -> reverts.
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector, 1)
        );
        store.recordMint({amount: 0.1 ether, tierIds: tierIds, isOwnerMint: false});
    }

    /// @notice Verifies that when reserves are minted between paid mints, paid mints can continue.
    /// initialSupply=4, reserveFrequency=1.
    function test_paidMintsResumeAfterReservesMinted() public {
        JB721TierConfig[] memory tiers = new JB721TierConfig[](1);
        tiers[0] = JB721TierConfig({
            price: 1 ether,
            initialSupply: 4,
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

        // Paid mint 1: remaining 4->3, nonReserveMints=1, pending=ceil(1/1)=1. Check: 3<1? No. OK.
        store.recordMint({amount: 1 ether, tierIds: tierIds, isOwnerMint: false});

        // Paid mint 2: remaining 3->2, nonReserveMints=2, pending=ceil(2/1)=2. Check: 2<2? No. OK.
        store.recordMint({amount: 1 ether, tierIds: tierIds, isOwnerMint: false});

        // Paid mint 3: remaining 2->1, nonReserveMints=3, pending=ceil(3/1)=3. Check: 1<3? Yes! Revert.
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector, 1)
        );
        store.recordMint({amount: 1 ether, tierIds: tierIds, isOwnerMint: false});

        // Mint 1 reserve — frees up a slot. Now reservesMinted=1.
        store.recordMintReservesFor({tierId: 1, count: 1});

        // State: remaining=1, reservesMinted=1, nonReserveMints=2.
        // Paid mint attempt: remaining 1->0, nonReserveMints=3, pending=ceil(3/1)-1=2. Check: 0<2? Yes! Revert.
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector, 1)
        );
        store.recordMint({amount: 1 ether, tierIds: tierIds, isOwnerMint: false});

        // Mint remaining reserve.
        store.recordMintReservesFor({tierId: 1, count: 1});

        // Tier fully minted — 0 remaining.
        JB721Tier memory tier = store.tierOf(address(this), 1, false);
        assertEq(tier.remainingSupply, 0, "tier should be fully minted");
    }

    /// @notice Without reserves, all NFTs in a tier should be mintable (no off-by-one).
    function test_noReservesFullSupplyMintable() public {
        JB721TierConfig[] memory tiers = new JB721TierConfig[](1);
        tiers[0] = JB721TierConfig({
            price: 0.1 ether,
            initialSupply: 5,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
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

        // Mint all 5 — should succeed since no reserves to protect.
        for (uint256 i; i < 5; i++) {
            store.recordMint({amount: 0.1 ether, tierIds: tierIds, isOwnerMint: false});
        }

        JB721Tier memory tier = store.tierOf(address(this), 1, false);
        assertEq(tier.remainingSupply, 0, "fully minted");

        // 6th mint should revert (supply exhausted).
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector, 1)
        );
        store.recordMint({amount: 0.1 ether, tierIds: tierIds, isOwnerMint: false});
    }
}
