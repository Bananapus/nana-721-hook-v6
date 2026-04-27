// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UnitTestSetup} from "../utils/UnitTestSetup.sol";
import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "../../src/interfaces/IJB721TokenUriResolver.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";

contract FutureTierPoC is UnitTestSetup {
    function test_futureTierRemovalPersistsIntoNewTierAndBricksMint() external {
        hook = _initHookDefaultTiers(0);

        uint256[] memory futureTierIds = new uint256[](1);
        futureTierIds[0] = 1;

        // L-18 FIX: Removing a future (nonexistent) tier ID now reverts,
        // preventing the "born removed" bug entirely.
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_UnrecognizedTier.selector, 1));
        hook.adjustTiers(new JB721TierConfig[](0), futureTierIds);
    }

    function test_futureTierUriCanBePoisonedBeforeTierExists() external {
        hook = _initHookDefaultTiers(0);

        bytes32 poisonedUri = bytes32(uint256(0x1234));

        vm.prank(owner);
        hook.setMetadata("", "", "", "", IJB721TokenUriResolver(address(hook)), 1, poisonedUri);

        (JB721TierConfig[] memory tiersToAdd,) = _createTiers(defaultTierConfig, 1);
        tiersToAdd[0].encodedIPFSUri = bytes32(0);

        vm.prank(owner);
        hook.adjustTiers(tiersToAdd, new uint256[](0));

        assertEq(hook.STORE().encodedIPFSUriOf(address(hook), 1), poisonedUri, "future tier inherited stale uri");
    }
}
