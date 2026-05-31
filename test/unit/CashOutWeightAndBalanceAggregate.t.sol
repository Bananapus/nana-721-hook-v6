// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {JB721Tier} from "../../src/structs/JB721Tier.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

/// @notice Unit tests for the O(1) `totalCashOutWeightOf` and `balanceOf` running aggregates. This test contract acts
/// as the hook (so `msg.sender == this` in the store) and drives the record* functions directly.
contract CashOutWeightAndBalanceAggregateTest is Test {
    JB721TiersHookStore store;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        store = new JB721TiersHookStore();
    }

    function _config(
        uint104 price,
        uint32 supply,
        uint16 freq,
        address beneficiary
    )
        internal
        pure
        returns (JB721TierConfig memory c)
    {
        c = JB721TierConfig({
            price: price,
            initialSupply: supply,
            votingUnits: 0,
            reserveFrequency: freq,
            reserveBeneficiary: beneficiary,
            encodedIpfsUri: bytes32(0),
            category: 0,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: true,
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
    }

    /// @dev Recompute the cash-out weight the way the original O(maxTierId) loop did, for cross-checking the aggregate.
    function _recomputeWeight() internal view returns (uint256 expected) {
        uint256 maxTier = store.maxTierIdOf(address(this));
        for (uint256 i = 1; i <= maxTier; i++) {
            JB721Tier memory tier = store.tierOf(address(this), i, false);
            uint256 burned = store.numberOfBurnedFor(address(this), i);
            if (tier.initialSupply == tier.remainingSupply && burned == 0) continue;
            uint256 pending = store.numberOfPendingReservesFor(address(this), i);
            expected += tier.price * ((tier.initialSupply - (tier.remainingSupply + burned)) + pending);
        }
    }

    function _mint(uint256 tierId, uint256 count) internal returns (uint256[] memory tokenIds) {
        uint16[] memory tierIds = new uint16[](count);
        for (uint256 i; i < count; i++) {
            tierIds[i] = uint16(tierId);
        }
        (tokenIds,,) = store.recordMint(type(uint256).max, tierIds, true);
    }

    function test_weightAggregate_trackingThroughMintReserveBurn() public {
        // Tier 1: price 1e18, no reserves. Tier 2: price 2e18, reserveFrequency 10, beneficiary alice.
        JB721TierConfig[] memory configs = new JB721TierConfig[](2);
        configs[0] = _config(1e18, 100, 0, address(0));
        configs[1] = _config(2e18, 100, 10, alice);
        store.recordAddTiers(configs);

        // Adding tiers contributes nothing (no mints yet) — and spamming empty tiers stays free.
        assertEq(store.totalCashOutWeightOf(address(this)), 0, "empty tiers contribute zero");

        // Mint 3 of tier 1: weight += 3 * 1e18.
        _mint(1, 3);
        assertEq(store.totalCashOutWeightOf(address(this)), 3e18, "tier1 mints");

        // Mint 10 of tier 2: 10 outstanding + 1 accrued pending reserve (ceil(10/10)) at 2e18 each = 22e18.
        _mint(2, 10);
        assertEq(store.totalCashOutWeightOf(address(this)), 3e18 + 22e18, "tier2 mints + pending reserve");
        assertEq(store.totalCashOutWeightOf(address(this)), _recomputeWeight(), "aggregate == recompute");

        // Reserve mint is weight-neutral: one pending reserve simply becomes one outstanding NFT.
        uint256 before = store.totalCashOutWeightOf(address(this));
        store.recordMintReservesFor(2, 1);
        assertEq(store.totalCashOutWeightOf(address(this)), before, "reserve mint is weight-neutral");
        assertEq(store.totalCashOutWeightOf(address(this)), _recomputeWeight(), "aggregate == recompute after reserve");

        // Burn one tier-1 NFT: weight -= 1e18.
        uint256[] memory t1 = _mint(1, 1); // mint one more to burn (keeps prior assertions clean)
        uint256 afterExtraMint = store.totalCashOutWeightOf(address(this));
        store.recordBurn(t1);
        assertEq(store.totalCashOutWeightOf(address(this)), afterExtraMint - 1e18, "burn removes one outstanding");
        assertEq(store.totalCashOutWeightOf(address(this)), _recomputeWeight(), "aggregate == recompute after burn");
    }

    function test_balanceAggregate_mintTransferBurn() public {
        JB721TierConfig[] memory configs = new JB721TierConfig[](1);
        configs[0] = _config(1e18, 100, 0, address(0));
        store.recordAddTiers(configs);

        // Simulate the hook recording mints to alice (transfer from 0 -> alice).
        store.recordTransferForTier(1, address(0), alice);
        store.recordTransferForTier(1, address(0), alice);
        store.recordTransferForTier(1, address(0), alice);
        assertEq(store.balanceOf(address(this), alice), 3, "alice has 3");

        // Transfer one alice -> bob.
        store.recordTransferForTier(1, alice, bob);
        assertEq(store.balanceOf(address(this), alice), 2, "alice has 2 after transfer");
        assertEq(store.balanceOf(address(this), bob), 1, "bob has 1");

        // Burn one of alice's (transfer alice -> 0).
        store.recordTransferForTier(1, alice, address(0));
        assertEq(store.balanceOf(address(this), alice), 1, "alice has 1 after burn");

        // balanceOf must equal the sum of per-tier balances.
        assertEq(store.balanceOf(address(this), alice), store.tierBalanceOf(address(this), alice, 1), "alice agg==tier");
        assertEq(store.balanceOf(address(this), bob), store.tierBalanceOf(address(this), bob, 1), "bob agg==tier");
    }

    /// @notice Spamming thousands of empty tiers leaves cash-out weight at zero and O(1) — the brick is impossible.
    function test_weightAggregate_emptyTierSpamStaysZeroAndCheap() public {
        JB721TierConfig[] memory configs = new JB721TierConfig[](500);
        for (uint256 i; i < 500; i++) {
            configs[i] = _config(1e18, 1000, 0, address(0));
        }
        store.recordAddTiers(configs);
        store.recordAddTiers(configs); // 1000 tiers total

        assertEq(store.maxTierIdOf(address(this)), 1000, "1000 tiers");
        // The read is O(1): it returns the aggregate (0) regardless of tier count.
        assertEq(store.totalCashOutWeightOf(address(this)), 0, "empty-tier spam contributes zero");
    }
}
