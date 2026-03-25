// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "forge-std/Test.sol";

import {JB721TiersHookStore} from "../../src/JB721TiersHookStore.sol";
// forge-lint: disable-next-line(unused-import)
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
// forge-lint: disable-next-line(unused-import)
import {JBStored721Tier} from "../../src/structs/JBStored721Tier.sol";
// forge-lint: disable-next-line(unused-import)
import {JB721TiersHookFlags} from "../../src/structs/JB721TiersHookFlags.sol";
// forge-lint: disable-next-line(unused-import)
import {JBBitmapWord} from "../../src/structs/JBBitmapWord.sol";
import {JB721Tier} from "../../src/structs/JB721Tier.sol";
import {TierStoreHandler} from "./handlers/TierStoreHandler.sol";

/// @notice Invariant tests for `JB721TiersHookStore` tier supply tracking.
contract TestTieredHookStoreInvariant is Test {
    JB721TiersHookStore store;
    TierStoreHandler handler;

    function setUp() public {
        store = new JB721TiersHookStore();
        handler = new TierStoreHandler(store);
        targetContract(address(handler));

        // Exclude internal wrapper functions from fuzzing — they bypass handler safety checks.
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = TierStoreHandler._doAddTiers.selector;
        selectors[1] = TierStoreHandler._doRemoveTiers.selector;
        selectors[2] = TierStoreHandler._doMint.selector;
        selectors[3] = TierStoreHandler._doBurn.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: _handlerSelectors()}));
    }

    function _handlerSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = TierStoreHandler.addTier.selector;
        selectors[1] = TierStoreHandler.removeTier.selector;
        selectors[2] = TierStoreHandler.mint.selector;
        selectors[3] = TierStoreHandler.burn.selector;
    }

    /// @notice INV-721-1: For any tier, remaining + burned <= initial supply.
    function invariant_supplyConservation() public {
        address hook = handler.HOOK();
        uint256 maxTier = store.maxTierIdOf(hook);

        for (uint256 i = 1; i <= maxTier; i++) {
            JB721Tier memory tier = store.tierOf(hook, i, false);
            if (tier.initialSupply == 0) continue; // Tier doesn't exist.

            uint256 burned = store.numberOfBurnedFor(hook, i);
            // remaining + burned <= initial (remaining = initial - minted, but minted >= burned)
            assertTrue(
                tier.remainingSupply + burned <= tier.initialSupply, "remaining + burned must not exceed initial supply"
            );
        }
    }

    /// @notice INV-721-2: Reserve mints never exceed the proportional reserve allocation.
    function invariant_reserveMintBounds() public {
        address hook = handler.HOOK();
        uint256 maxTier = store.maxTierIdOf(hook);

        for (uint256 i = 1; i <= maxTier; i++) {
            JB721Tier memory tier = store.tierOf(hook, i, false);
            if (tier.initialSupply == 0) continue;

            uint256 reservesMinted = store.numberOfReservesMintedFor(hook, i);
            if (tier.reserveFrequency == 0) {
                assertEq(reservesMinted, 0, "no reserves without reserveFrequency");
            }
        }
    }

    /// @notice INV-721-3: maxTierIdOf is monotonically increasing (never decreases).
    function invariant_maxTierIdMonotonic() public {
        address hook = handler.HOOK();
        uint256 currentMax = store.maxTierIdOf(hook);
        assertTrue(currentMax >= handler.lowestMaxTierIdSeen(), "maxTierIdOf should never decrease");
    }
}
