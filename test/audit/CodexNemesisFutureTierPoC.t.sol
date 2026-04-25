// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UnitTestSetup} from "../utils/UnitTestSetup.sol";
import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "../../src/interfaces/IJB721TokenUriResolver.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";

contract CodexNemesisFutureTierPoC is UnitTestSetup {
    function test_futureTierRemovalPersistsIntoNewTierAndBricksMint() external {
        hook = _initHookDefaultTiers(0);

        uint256[] memory futureTierIds = new uint256[](1);
        futureTierIds[0] = 1;

        vm.prank(owner);
        hook.adjustTiers(new JB721TierConfig[](0), futureTierIds);

        (JB721TierConfig[] memory tiersToAdd,) = _createTiers(defaultTierConfig, 1);

        vm.prank(owner);
        hook.adjustTiers(tiersToAdd, new uint256[](0));

        assertTrue(hook.STORE().isTierRemoved(address(hook), 1), "future removal flag should persist");

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        JB721TiersHookStore store = JB721TiersHookStore(address(hook.STORE()));

        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_TierRemoved.selector, 1)
        );
        vm.prank(address(hook));
        store.recordMint(type(uint256).max, tierIds, false);
    }

    function test_futureTierUriCanBePoisonedBeforeTierExists() external {
        hook = _initHookDefaultTiers(0);

        bytes32 poisonedUri = bytes32(uint256(0x1234));

        vm.prank(owner);
        hook.setMetadata(
            "",
            "",
            "",
            "",
            IJB721TokenUriResolver(address(hook)),
            1,
            poisonedUri
        );

        (JB721TierConfig[] memory tiersToAdd,) = _createTiers(defaultTierConfig, 1);
        tiersToAdd[0].encodedIPFSUri = bytes32(0);

        vm.prank(owner);
        hook.adjustTiers(tiersToAdd, new uint256[](0));

        assertEq(hook.STORE().encodedIPFSUriOf(address(hook), 1), poisonedUri, "future tier inherited stale uri");
    }
}
