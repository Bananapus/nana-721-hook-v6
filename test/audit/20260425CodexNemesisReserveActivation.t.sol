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

    /// @notice Sold-out tiers must not produce phantom pending reserves
    /// when a later tier sets a default reserve beneficiary.
    function test_soldOutTier_noPhantomReserves_afterDefaultBeneficiaryChange() external {
        // Step 1: Add a tier with reserve frequency but no beneficiary.
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

        // Step 2: Sell out the tier completely.
        uint16[] memory tierIds = new uint16[](10);
        for (uint256 i; i < tierIds.length; i++) {
            tierIds[i] = 1;
        }
        store.recordMint({amount: 10, tierIds: tierIds, isOwnerMint: false});

        // Verify: sold out, no pending reserves, weight = 10 (10 minted * price 1).
        JB721Tier memory beforeDefault = store.tierOf({hook: address(this), id: 1, includeResolvedUri: false});
        assertEq(beforeDefault.remainingSupply, 0, "tier should be sold out");
        assertEq(store.numberOfPendingReservesFor({hook: address(this), tierId: 1}), 0, "no reserves before default");
        assertEq(store.totalCashOutWeight(address(this)), 10, "weight should be 10");

        // Step 3: Add a new tier that sets itself as the default reserve beneficiary.
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

        // Verify: the sold-out tier must NOT have phantom pending reserves.
        JB721Tier memory afterDefault = store.tierOf({hook: address(this), id: 1, includeResolvedUri: false});
        assertEq(afterDefault.remainingSupply, 0, "tier still sold out");
        assertEq(afterDefault.reserveBeneficiary, address(0xBEEF), "default beneficiary propagated");
        assertEq(
            store.numberOfPendingReservesFor({hook: address(this), tierId: 1}),
            0,
            "sold-out tier must have 0 pending reserves"
        );
        assertEq(store.totalCashOutWeight(address(this)), 10, "weight must stay at 10 - no phantom dilution");
    }

    /// @notice Regression: non-sold-out tiers with a default beneficiary still accumulate reserves normally.
    function test_nonSoldOutTier_reservesStillWork_afterDefaultBeneficiaryChange() external {
        // Add a tier with reserve frequency but no beneficiary.
        JB721TierConfig[] memory initialTiers = new JB721TierConfig[](1);
        initialTiers[0] = _tier({
            price: 1,
            initialSupply: 100,
            reserveFrequency: 5,
            reserveBeneficiary: address(0),
            useReserveBeneficiaryAsDefault: false,
            category: 1
        });
        store.recordAddTiers(initialTiers);

        // Mint 50 out of 100 — NOT sold out.
        uint16[] memory tierIds = new uint16[](50);
        for (uint256 i; i < tierIds.length; i++) {
            tierIds[i] = 1;
        }
        store.recordMint({amount: 50, tierIds: tierIds, isOwnerMint: false});

        // No reserves yet (no beneficiary).
        assertEq(store.numberOfPendingReservesFor({hook: address(this), tierId: 1}), 0);

        // Set a default beneficiary via a new tier.
        JB721TierConfig[] memory laterTiers = new JB721TierConfig[](1);
        laterTiers[0] = _tier({
            price: 1,
            initialSupply: 100,
            reserveFrequency: 5,
            reserveBeneficiary: address(0xBEEF),
            useReserveBeneficiaryAsDefault: true,
            category: 2
        });
        store.recordAddTiers(laterTiers);

        // Now tier 1 should have pending reserves: 50 non-reserve mints / 5 frequency = 10 reserves.
        assertEq(
            store.numberOfPendingReservesFor({hook: address(this), tierId: 1}),
            10,
            "non-sold-out tier should have 10 pending reserves"
        );

        // And those reserves should be mintable (tier has remaining supply).
        uint256[] memory tokenIds = store.recordMintReservesFor({tierId: 1, count: 10});
        assertEq(tokenIds.length, 10, "should mint 10 reserve tokens");

        // After minting, pending reserves should be 0.
        assertEq(store.numberOfPendingReservesFor({hook: address(this), tierId: 1}), 0);
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
