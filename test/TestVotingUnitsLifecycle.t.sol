// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../src/interfaces/IJB721TiersHookStore.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title TestVotingUnitsLifecycle
/// @notice Tests that voting units are correctly tracked through the full NFT lifecycle:
/// mint, transfer, and burn. Verifies that the store's votingUnitsOf aggregation stays
/// consistent as token ownership changes across tiers.
contract TestVotingUnitsLifecycle is UnitTestSetup {
    using stdStorage for StdStorage;

    // ---------------------------------------------------------------
    // Test 1: Mint -> Transfer -> Burn lifecycle for voting units
    // ---------------------------------------------------------------
    /// @notice Verifies that custom voting units (useVotingUnits=true) are correctly tracked
    /// through the full lifecycle: mint to user A, transfer to user B, burn by user B.
    function test_votingUnits_mintTransferBurn_lifecycle() public {
        // Configure a tier with custom voting units.
        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook testHook = _initializeForTestHook(1);
        IJB721TiersHookStore hookStore = testHook.STORE();

        address userA = makeAddr("userA");
        address userB = makeAddr("userB");

        // --- Mint: NFT goes to userA ---
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        testHook.mintFor(tiersToMint, userA);

        uint256 tokenId = _generateTokenId(1, 1);

        // Verify userA has 100 voting units.
        assertEq(
            hookStore.votingUnitsOf(address(testHook), userA), 100, "UserA should have 100 voting units after mint"
        );
        assertEq(hookStore.votingUnitsOf(address(testHook), userB), 0, "UserB should have 0 voting units after mint");

        // --- Transfer: NFT from userA to userB ---
        vm.prank(userA);
        IERC721(address(testHook)).transferFrom(userA, userB, tokenId);

        // Verify voting units moved from userA to userB.
        assertEq(
            hookStore.votingUnitsOf(address(testHook), userA), 0, "UserA should have 0 voting units after transfer"
        );
        assertEq(
            hookStore.votingUnitsOf(address(testHook), userB), 100, "UserB should have 100 voting units after transfer"
        );

        // --- Burn: userB burns the NFT ---
        uint256[] memory tokensToBurn = new uint256[](1);
        tokensToBurn[0] = tokenId;
        vm.prank(address(0)); // burn uses _burn internally via ForTest
        testHook.burn(tokensToBurn);

        // Verify both users have 0 voting units after burn.
        assertEq(hookStore.votingUnitsOf(address(testHook), userA), 0, "UserA should have 0 voting units after burn");
        assertEq(hookStore.votingUnitsOf(address(testHook), userB), 0, "UserB should have 0 voting units after burn");
    }

    // ---------------------------------------------------------------
    // Test 2: Multi-tier voting units aggregation
    // ---------------------------------------------------------------
    /// @notice Verifies that voting units from multiple tiers aggregate correctly
    /// and update properly when NFTs are transferred between users.
    function test_votingUnits_multiTier_aggregation() public {
        // Configure tiers with different custom voting units.
        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.useVotingUnits = true;

        ForTest_JB721TiersHook testHook = _initializeForTestHook(3);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Set custom voting units for each tier.
        // Tier 1 = 100, Tier 2 = 200, Tier 3 = 500.
        testHook.test_store().ForTest_setTierVotingUnits(address(testHook), 1, 100);
        testHook.test_store().ForTest_setTierVotingUnits(address(testHook), 2, 200);
        testHook.test_store().ForTest_setTierVotingUnits(address(testHook), 3, 500);

        address user = makeAddr("user");
        address recipient = makeAddr("recipient");

        // --- Mint one NFT from each tier to the same user ---
        uint16[] memory tier1 = new uint16[](1);
        tier1[0] = 1;
        uint16[] memory tier2 = new uint16[](1);
        tier2[0] = 2;
        uint16[] memory tier3 = new uint16[](1);
        tier3[0] = 3;

        vm.startPrank(owner);
        testHook.mintFor(tier1, user);
        testHook.mintFor(tier2, user);
        testHook.mintFor(tier3, user);
        vm.stopPrank();

        // Verify total voting units = 100 + 200 + 500 = 800.
        assertEq(hookStore.votingUnitsOf(address(testHook), user), 800, "User should have 800 voting units total");

        // --- Transfer tier 3 NFT (500 units) to recipient ---
        uint256 tier3TokenId = _generateTokenId(3, 1);
        vm.prank(user);
        IERC721(address(testHook)).transferFrom(user, recipient, tier3TokenId);

        // Verify user now has 300, recipient has 500.
        assertEq(
            hookStore.votingUnitsOf(address(testHook), user),
            300,
            "User should have 300 voting units after transferring tier 3"
        );
        assertEq(
            hookStore.votingUnitsOf(address(testHook), recipient),
            500,
            "Recipient should have 500 voting units from tier 3"
        );

        // --- Transfer tier 1 NFT (100 units) to recipient ---
        uint256 tier1TokenId = _generateTokenId(1, 1);
        vm.prank(user);
        IERC721(address(testHook)).transferFrom(user, recipient, tier1TokenId);

        // Verify user now has 200, recipient has 600.
        assertEq(
            hookStore.votingUnitsOf(address(testHook), user),
            200,
            "User should have 200 voting units after transferring tier 1"
        );
        assertEq(
            hookStore.votingUnitsOf(address(testHook), recipient),
            600,
            "Recipient should have 600 voting units from tiers 1 and 3"
        );
    }

    // ---------------------------------------------------------------
    // Test 3: Price-based voting units (useVotingUnits=false)
    // ---------------------------------------------------------------
    /// @notice Verifies that when useVotingUnits is false, the tier price is used as voting power.
    function test_votingUnits_priceBasedVoting_lifecycle() public {
        // Configure tiers WITHOUT custom voting units (price-based voting).
        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.useVotingUnits = false;
        defaultTierConfig.votingUnits = 0;

        ForTest_JB721TiersHook testHook = _initializeForTestHook(3);
        IJB721TiersHookStore hookStore = testHook.STORE();

        address user = makeAddr("user");
        address recipient = makeAddr("recipient");

        // Default tiers have prices: tier 1 = 10, tier 2 = 20, tier 3 = 30 (from _createTiers).
        uint16[] memory tier1 = new uint16[](1);
        tier1[0] = 1;
        uint16[] memory tier2 = new uint16[](1);
        tier2[0] = 2;
        uint16[] memory tier3 = new uint16[](1);
        tier3[0] = 3;

        vm.startPrank(owner);
        testHook.mintFor(tier1, user);
        testHook.mintFor(tier2, user);
        testHook.mintFor(tier3, user);
        vm.stopPrank();

        // Verify total voting units = 10 + 20 + 30 = 60 (prices).
        assertEq(hookStore.votingUnitsOf(address(testHook), user), 60, "User should have 60 price-based voting units");

        // Transfer tier 2 (price 20).
        uint256 tier2TokenId = _generateTokenId(2, 1);
        vm.prank(user);
        IERC721(address(testHook)).transferFrom(user, recipient, tier2TokenId);

        assertEq(
            hookStore.votingUnitsOf(address(testHook), user),
            40,
            "User should have 40 voting units after transferring tier 2"
        );
        assertEq(
            hookStore.votingUnitsOf(address(testHook), recipient),
            20,
            "Recipient should have 20 voting units from tier 2"
        );
    }

    // ---------------------------------------------------------------
    // Test 4: Multiple NFTs from the same tier
    // ---------------------------------------------------------------
    /// @notice Verifies that voting units scale correctly when a user owns multiple NFTs from one tier.
    function test_votingUnits_multipleMintsSameTier() public {
        // Configure tier with custom voting units.
        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.useVotingUnits = true;
        defaultTierConfig.votingUnits = 50;

        ForTest_JB721TiersHook testHook = _initializeForTestHook(1);
        IJB721TiersHookStore hookStore = testHook.STORE();

        address user = makeAddr("user");

        // Mint 3 NFTs from tier 1 to the same user.
        uint16[] memory tiersToMint = new uint16[](3);
        tiersToMint[0] = 1;
        tiersToMint[1] = 1;
        tiersToMint[2] = 1;

        vm.prank(owner);
        testHook.mintFor(tiersToMint, user);

        // Verify total voting units = 50 * 3 = 150.
        assertEq(hookStore.votingUnitsOf(address(testHook), user), 150, "User should have 150 voting units (3 x 50)");

        // Transfer one NFT away.
        address recipient = makeAddr("recipient");
        uint256 tokenId1 = _generateTokenId(1, 1);
        vm.prank(user);
        IERC721(address(testHook)).transferFrom(user, recipient, tokenId1);

        // Verify voting units: user = 100, recipient = 50.
        assertEq(
            hookStore.votingUnitsOf(address(testHook), user),
            100,
            "User should have 100 voting units after transferring 1"
        );
        assertEq(hookStore.votingUnitsOf(address(testHook), recipient), 50, "Recipient should have 50 voting units");
    }

    // ---------------------------------------------------------------
    // Test 5: Voting units are zero for addresses with no NFTs
    // ---------------------------------------------------------------
    /// @notice Verifies that addresses with no NFTs always return 0 voting units.
    function test_votingUnits_zeroForNonHolders() public {
        defaultTierConfig.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook testHook = _initializeForTestHook(5);
        IJB721TiersHookStore hookStore = testHook.STORE();

        address nonHolder = makeAddr("nonHolder");

        // Verify zero voting units for an address that never held any NFTs.
        assertEq(hookStore.votingUnitsOf(address(testHook), nonHolder), 0, "Non-holder should have 0 voting units");
    }

    // ---------------------------------------------------------------
    // Test 6: Voting units with mixed tier configs
    // ---------------------------------------------------------------
    /// @notice Verifies that voting units work correctly when some tiers use custom voting units
    /// and others use price-based voting. The tier with useVotingUnits=false should use price.
    function test_votingUnits_mixedTierConfigs() public {
        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook testHook = _initializeForTestHook(3);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Override tier 2 to NOT use custom voting units (price-based).
        // Tier 2 price from _createTiers is 20.
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
                    packedBools: testHook.test_store().ForTest_packBools(true, false, false, false, false),
                    splitPercent: 0
                })
            );
        // Clear tier 2's custom voting units (so it falls back to price).
        testHook.test_store().ForTest_setTierVotingUnits(address(testHook), 2, 0);

        address user = makeAddr("user");

        // Mint one NFT from each tier.
        uint16[] memory tier1 = new uint16[](1);
        tier1[0] = 1;
        uint16[] memory tier2 = new uint16[](1);
        tier2[0] = 2;
        uint16[] memory tier3 = new uint16[](1);
        tier3[0] = 3;

        vm.startPrank(owner);
        testHook.mintFor(tier1, user);
        testHook.mintFor(tier2, user);
        testHook.mintFor(tier3, user);
        vm.stopPrank();

        // Tier 1: custom voting units = 100
        // Tier 2: price-based = 20 (useVotingUnits=false, so uses price)
        // Tier 3: custom voting units = 100
        // Total: 100 + 20 + 100 = 220
        assertEq(hookStore.votingUnitsOf(address(testHook), user), 220, "User should have 220 mixed voting units");
    }
}
