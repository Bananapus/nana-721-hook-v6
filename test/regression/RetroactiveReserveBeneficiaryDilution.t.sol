// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {JBAfterPayRecordedContext} from "@bananapus/core-v6/src/structs/JBAfterPayRecordedContext.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";
import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";

contract RetroactiveReserveBeneficiaryDilution is UnitTestSetup {
    /// @notice Creating a tier with reserveFrequency > 0 but no beneficiary (tier-specific or default) now reverts,
    /// preventing the phantom reserve scenario where a later default beneficiary retroactively inflates
    /// totalCashOutWeight and dilutes existing holders.
    function test_adjustTier_reverts_when_reserve_has_no_beneficiary() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);

        JB721TierConfig[] memory tier1 = new JB721TierConfig[](1);
        tier1[0] = JB721TierConfig({
            price: 1 ether,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 2,
            reserveBeneficiary: address(0),
            encodedIpfsUri: bytes32(uint256(0x1234)),
            category: 1,
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

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_MissingReserveBeneficiary.selector, 1)
        );
        testHook.adjustTiers(tier1, new uint256[](0));
    }

    /// @notice A tier with reserveFrequency > 0 succeeds when an explicit beneficiary is provided.
    function test_adjustTier_succeeds_with_explicit_reserve_beneficiary() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);

        JB721TierConfig[] memory tier1 = new JB721TierConfig[](1);
        tier1[0] = JB721TierConfig({
            price: 1 ether,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 2,
            reserveBeneficiary: owner,
            encodedIpfsUri: bytes32(uint256(0x1234)),
            category: 1,
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

        vm.prank(owner);
        testHook.adjustTiers(tier1, new uint256[](0));

        assertEq(
            testHook.STORE().reserveBeneficiaryOf(address(testHook), 1),
            owner,
            "tier-specific beneficiary should be set"
        );
    }

    /// @notice A tier with reserveFrequency > 0 and no explicit beneficiary succeeds when a default beneficiary
    /// was previously set by an earlier tier.
    function test_adjustTier_succeeds_with_default_reserve_beneficiary() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);

        // Add two tiers: first sets the default beneficiary, second relies on it.
        JB721TierConfig[] memory tiers = new JB721TierConfig[](2);

        // Tier 1: sets default beneficiary via useReserveBeneficiaryAsDefault.
        tiers[0] = JB721TierConfig({
            price: 1 ether,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 2,
            reserveBeneficiary: owner,
            encodedIpfsUri: bytes32(uint256(0x1234)),
            category: 1,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: true,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        // Tier 2: relies on the default beneficiary (no explicit one).
        tiers[1] = JB721TierConfig({
            price: 2 ether,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 3,
            reserveBeneficiary: address(0),
            encodedIpfsUri: bytes32(uint256(0x5678)),
            category: 2,
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

        vm.prank(owner);
        testHook.adjustTiers(tiers, new uint256[](0));

        // Tier 2 should inherit the default beneficiary set by tier 1.
        assertEq(
            testHook.STORE().reserveBeneficiaryOf(address(testHook), 2),
            owner,
            "tier 2 should inherit default beneficiary"
        );
    }
}
