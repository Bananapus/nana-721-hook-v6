// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";

/// @notice Regression test for L-34: defaultReserveBeneficiaryOf is globally overwritten when adding a tier with
/// useReserveBeneficiaryAsDefault=true.
contract Test_L34_ReserveBeneficiaryOverwrite is UnitTestSetup {
    using stdStorage for StdStorage;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    /// @notice Verify that adding a tier with useReserveBeneficiaryAsDefault=true overwrites the global default
    /// and emits the SetDefaultReserveBeneficiary event.
    function test_addTierWithDefaultBeneficiary_overwritesGlobal() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add tier 1: alice as default reserve beneficiary.
        JB721TierConfig[] memory tier1Configs = new JB721TierConfig[](1);
        tier1Configs[0].price = 1 ether;
        tier1Configs[0].initialSupply = uint32(100);
        tier1Configs[0].category = uint24(1);
        tier1Configs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tier1Configs[0].reserveFrequency = 5;
        tier1Configs[0].reserveBeneficiary = alice;
        tier1Configs[0].useReserveBeneficiaryAsDefault = true;

        vm.prank(address(testHook));
        uint256[] memory tier1Ids = hookStore.recordAddTiers(tier1Configs);

        // Verify alice is the default reserve beneficiary.
        assertEq(hookStore.defaultReserveBeneficiaryOf(address(testHook)), alice);

        // Verify tier 1 uses alice as its reserve beneficiary (via the default).
        assertEq(hookStore.reserveBeneficiaryOf(address(testHook), tier1Ids[0]), alice);

        // Add tier 2: no useReserveBeneficiaryAsDefault, with a per-tier beneficiary.
        JB721TierConfig[] memory tier2Configs = new JB721TierConfig[](1);
        tier2Configs[0].price = 2 ether;
        tier2Configs[0].initialSupply = uint32(100);
        tier2Configs[0].category = uint24(2);
        tier2Configs[0].encodedIPFSUri = bytes32(uint256(0x5678));
        tier2Configs[0].reserveFrequency = 5;
        tier2Configs[0].reserveBeneficiary = bob;
        tier2Configs[0].useReserveBeneficiaryAsDefault = false;

        vm.prank(address(testHook));
        uint256[] memory tier2Ids = hookStore.recordAddTiers(tier2Configs);

        // Default should still be alice.
        assertEq(hookStore.defaultReserveBeneficiaryOf(address(testHook)), alice);

        // Tier 2 should use bob (tier-specific).
        assertEq(hookStore.reserveBeneficiaryOf(address(testHook), tier2Ids[0]), bob);

        // Now add tier 3: bob as the NEW default reserve beneficiary.
        // This should overwrite the default, affecting tier 1 which relies on the default.
        JB721TierConfig[] memory tier3Configs = new JB721TierConfig[](1);
        tier3Configs[0].price = 3 ether;
        tier3Configs[0].initialSupply = uint32(100);
        tier3Configs[0].category = uint24(3);
        tier3Configs[0].encodedIPFSUri = bytes32(uint256(0x9ABC));
        tier3Configs[0].reserveFrequency = 5;
        tier3Configs[0].reserveBeneficiary = bob;
        tier3Configs[0].useReserveBeneficiaryAsDefault = true;

        vm.prank(address(testHook));
        uint256[] memory tier3Ids = hookStore.recordAddTiers(tier3Configs);

        // Default should now be bob.
        assertEq(hookStore.defaultReserveBeneficiaryOf(address(testHook)), bob);

        // Tier 1 should now resolve to bob (the new default), NOT alice.
        // This is the documented global overwrite behavior.
        assertEq(hookStore.reserveBeneficiaryOf(address(testHook), tier1Ids[0]), bob);

        // Tier 2 should still use bob (tier-specific, unaffected by default change).
        assertEq(hookStore.reserveBeneficiaryOf(address(testHook), tier2Ids[0]), bob);

        // Tier 3 should also resolve to bob (via the default).
        assertEq(hookStore.reserveBeneficiaryOf(address(testHook), tier3Ids[0]), bob);
    }

    /// @notice Verify that the SetDefaultReserveBeneficiary event is emitted when the default changes.
    function test_addTierWithDefaultBeneficiary_emitsEvent() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tierConfigs[0].reserveFrequency = 5;
        tierConfigs[0].reserveBeneficiary = alice;
        tierConfigs[0].useReserveBeneficiaryAsDefault = true;

        // Expect the SetDefaultReserveBeneficiary event.
        vm.expectEmit(true, true, false, true, address(hookStore));
        emit JB721TiersHookStore.SetDefaultReserveBeneficiary({
            hook: address(testHook),
            newBeneficiary: alice,
            caller: address(testHook)
        });

        vm.prank(address(testHook));
        hookStore.recordAddTiers(tierConfigs);
    }

    /// @notice Verify that no event is emitted when the beneficiary is already the same.
    function test_addTierWithSameDefaultBeneficiary_noEvent() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // First, set alice as the default.
        JB721TierConfig[] memory tier1Configs = new JB721TierConfig[](1);
        tier1Configs[0].price = 1 ether;
        tier1Configs[0].initialSupply = uint32(100);
        tier1Configs[0].category = uint24(1);
        tier1Configs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tier1Configs[0].reserveFrequency = 5;
        tier1Configs[0].reserveBeneficiary = alice;
        tier1Configs[0].useReserveBeneficiaryAsDefault = true;

        vm.prank(address(testHook));
        hookStore.recordAddTiers(tier1Configs);

        // Now add another tier with the same default — no event should be emitted.
        JB721TierConfig[] memory tier2Configs = new JB721TierConfig[](1);
        tier2Configs[0].price = 2 ether;
        tier2Configs[0].initialSupply = uint32(100);
        tier2Configs[0].category = uint24(2);
        tier2Configs[0].encodedIPFSUri = bytes32(uint256(0x5678));
        tier2Configs[0].reserveFrequency = 5;
        tier2Configs[0].reserveBeneficiary = alice;
        tier2Configs[0].useReserveBeneficiaryAsDefault = true;

        // Record the logs to verify no SetDefaultReserveBeneficiary event is emitted.
        vm.recordLogs();

        vm.prank(address(testHook));
        hookStore.recordAddTiers(tier2Configs);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            // SetDefaultReserveBeneficiary event signature.
            assertTrue(
                logs[i].topics[0] != keccak256("SetDefaultReserveBeneficiary(address,address,address)"),
                "SetDefaultReserveBeneficiary should not be emitted when beneficiary unchanged"
            );
        }
    }
}
