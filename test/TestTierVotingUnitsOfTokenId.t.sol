// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../src/interfaces/IJB721TiersHookStore.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title TestTierVotingUnitsOfTokenId
/// @notice Tests the lightweight `tierVotingUnitsOfTokenId` getter that `JB721Checkpoints.onTransfer` relies on.
/// @dev The getter must return EXACTLY the same per-unit voting value as the `votingUnits` field built by the full
/// `tierOfTokenId(...)` struct getter, for both `useVotingUnits=true` (custom voting units) and `useVotingUnits=false`
/// (price-based) tiers — and a transfer must still move the correct voting power onto the new owner.
contract TestTierVotingUnitsOfTokenId is UnitTestSetup {
    /// @notice For a tier with `useVotingUnits=true`, the lightweight getter equals the full struct getter's
    /// `votingUnits` (the custom value), and a transfer moves that voting power. For a tier with
    /// `useVotingUnits=false`, both equal the tier price.
    function test_tierVotingUnitsOfTokenId_matchesFullStruct_andTransfersPower() public {
        // Configure tiers: by default `useVotingUnits=true` with a custom voting units value.
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 777;

        ForTest_JB721TiersHook testHook = _initializeForTestHook(2);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Tier 1: custom voting units = 777 (useVotingUnits = true).
        // Override tier 2 to be price-based (useVotingUnits = false). Tier 2's price from `_createTiers` is 20.
        testHook.test_store()
            .ForTest_setTier(
                address(testHook),
                2,
                JBStored721Tier({
                price: uint104(20),
                remainingSupply: uint32(100),
                initialSupply: uint32(100),
                reserveFrequency: uint16(0),
                category: uint24(100),
                discountPercent: uint8(0),
                // allowOwnerMint = true, useVotingUnits = false (3rd bool), all others false.
                packedBools: testHook.test_store().ForTest_packBools(true, false, false, false, false, false),
                splitPercent: 0
            })
            );
        // Clear tier 2's custom voting units so it cannot accidentally be read.
        testHook.test_store().ForTest_setTierVotingUnits(address(testHook), 2, 0);

        address userA = makeAddr("userA");
        address userB = makeAddr("userB");

        // --- Mint one NFT in each tier to userA ---
        uint16[] memory tier1 = new uint16[](1);
        tier1[0] = 1;
        uint16[] memory tier2 = new uint16[](1);
        tier2[0] = 2;

        vm.startPrank(owner);
        testHook.mintFor(tier1, userA);
        testHook.mintFor(tier2, userA);
        vm.stopPrank();

        uint256 tier1TokenId = _generateTokenId(1, 1);
        uint256 tier2TokenId = _generateTokenId(2, 1);

        // --- Assert the lightweight getter matches the full struct getter for BOTH tiers ---

        // Tier 1: useVotingUnits = true -> custom value 777.
        uint256 fullTier1 = hookStore.tierOfTokenId(address(testHook), tier1TokenId, false).votingUnits;
        assertEq(fullTier1, 777, "Tier 1 full-struct votingUnits should be the custom value");
        assertEq(
            hookStore.tierVotingUnitsOfTokenId(address(testHook), tier1TokenId),
            fullTier1,
            "Tier 1 lightweight getter must match full struct getter"
        );

        // Tier 2: useVotingUnits = false -> tier price 20.
        uint256 fullTier2 = hookStore.tierOfTokenId(address(testHook), tier2TokenId, false).votingUnits;
        assertEq(fullTier2, 20, "Tier 2 full-struct votingUnits should be the tier price");
        assertEq(
            hookStore.tierVotingUnitsOfTokenId(address(testHook), tier2TokenId),
            fullTier2,
            "Tier 2 lightweight getter must match full struct getter"
        );

        // --- Sanity: aggregate voting power before transfer = 777 + 20 = 797 ---
        assertEq(
            hookStore.votingUnitsOf(address(testHook), userA), 797, "UserA should hold 777 + 20 voting units after mint"
        );

        // --- Transfer the price-based (tier 2) NFT and assert voting power moved correctly ---
        vm.prank(userA);
        IERC721(address(testHook)).transferFrom(userA, userB, tier2TokenId);

        assertEq(
            hookStore.votingUnitsOf(address(testHook), userA),
            777,
            "UserA should retain only the tier 1 (777) voting units after transferring tier 2"
        );
        assertEq(
            hookStore.votingUnitsOf(address(testHook), userB),
            20,
            "UserB should receive the tier 2 price-based (20) voting units"
        );

        // --- Transfer the custom-voting-units (tier 1) NFT and assert voting power moved correctly ---
        vm.prank(userA);
        IERC721(address(testHook)).transferFrom(userA, userB, tier1TokenId);

        assertEq(
            hookStore.votingUnitsOf(address(testHook), userA),
            0,
            "UserA should hold 0 voting units after transferring both NFTs"
        );
        assertEq(
            hookStore.votingUnitsOf(address(testHook), userB),
            797,
            "UserB should hold all 777 + 20 voting units after both transfers"
        );
    }
}
