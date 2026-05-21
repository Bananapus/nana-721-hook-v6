// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";

/// @notice Regression coverage for category start pointers across separate tier-add batches.
contract CategoryStartPointerTest is UnitTestSetup {
    /// @notice Adding a later tier to an existing nonzero category must not hide the older tier from category queries.
    function test_recordAddTiers_sameCategorySeparateBatchesKeepsOlderTierVisible() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        JB721TierConfig[] memory firstBatch = new JB721TierConfig[](1);
        firstBatch[0] = _tierConfig({price: 1 ether, category: 3, encodedIpfsUri: bytes32(uint256(1))});

        vm.prank(address(testHook));
        uint256[] memory firstTierIds = hookStore.recordAddTiers(firstBatch);

        JB721TierConfig[] memory secondBatch = new JB721TierConfig[](1);
        secondBatch[0] = _tierConfig({price: 2 ether, category: 3, encodedIpfsUri: bytes32(uint256(2))});

        vm.prank(address(testHook));
        uint256[] memory secondTierIds = hookStore.recordAddTiers(secondBatch);

        uint256[] memory categories = new uint256[](1);
        categories[0] = 3;

        JB721Tier[] memory categoryTiers = hookStore.tiersOf({
            hook: address(testHook), categories: categories, includeResolvedUri: false, startingId: 0, size: 10
        });

        assertEq(categoryTiers.length, 2);
        // Same-category additions are inserted before older same-category tiers in the sorted linked list. The category
        // pointer must therefore move to the later tier, whose next link reaches the older tier.
        assertEq(categoryTiers[0].id, secondTierIds[0]);
        assertEq(categoryTiers[1].id, firstTierIds[0]);
        assertEq(categoryTiers[0].category, 3);
        assertEq(categoryTiers[1].category, 3);
    }

    function _tierConfig(
        uint104 price,
        uint24 category,
        bytes32 encodedIpfsUri
    )
        internal
        pure
        returns (JB721TierConfig memory config)
    {
        config.price = price;
        config.initialSupply = 100;
        config.encodedIpfsUri = encodedIpfsUri;
        config.category = category;
    }
}
