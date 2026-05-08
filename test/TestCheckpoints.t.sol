// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./utils/UnitTestSetup.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "./utils/ForTest_JB721TiersHook.sol";
import {JB721Checkpoints} from "../src/JB721Checkpoints.sol";
import {IJB721Checkpoints} from "../src/interfaces/IJB721Checkpoints.sol";
import {IJB721TiersHook} from "../src/interfaces/IJB721TiersHook.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title TestCheckpoints
/// @notice Tests the checkpoint module IVotes checkpointed voting power baked into the base hook:
/// delegation, checkpoints, transfer, multi-tier, burn, and module deployment.
contract TestCheckpoints is UnitTestSetup {
    /// @notice Deploys a ForTest hook with the given number of tiers.
    function _initializeHookWithCheckpoints(uint256 numberOfTiers) internal returns (ForTest_JB721TiersHook tiersHook) {
        (JB721TierConfig[] memory tierConfigs,) = _createTiers(defaultTierConfig, numberOfTiers);

        ForTest_JB721TiersHookStore hookStore = new ForTest_JB721TiersHookStore();

        tiersHook = new ForTest_JB721TiersHook(
            ForTest_JB721TiersHook.ForTestInitConfig({
                projectId: projectId,
                name: name,
                symbol: symbol,
                baseUri: baseUri,
                tokenUriResolver: IJB721TokenUriResolver(mockTokenUriResolver),
                contractUri: contractUri,
                tiers: tierConfigs,
                flags: JB721TiersHookFlags({
                    preventOverspending: false,
                    issueTokensForSplits: false,
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: true
                })
            }),
            IJBDirectory(mockJBDirectory),
            IJBPrices(mockJBPrices),
            IJBRulesets(mockJBRulesets),
            IJB721TiersHookStore(address(hookStore)),
            IJBSplits(mockJBSplits)
        );

        tiersHook.transferOwnership(owner);
    }

    // -------------------------------------------------------------------
    // Test 1: Checkpoint module is deployed lazily on first transfer
    // -------------------------------------------------------------------
    function test_checkpointModule_isDeployedLazily() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        // CHECKPOINTS should NOT be deployed after initialization (lazy deployment).
        assertTrue(
            address(tiersHook.CHECKPOINTS()) == address(0),
            "Checkpoint module should not be deployed after initialization"
        );

        // Mint a token to trigger lazy deployment.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, owner);

        // CHECKPOINTS should now be deployed after the first mint.
        assertTrue(
            address(tiersHook.CHECKPOINTS()) != address(0), "Checkpoint module should be deployed after first mint"
        );
    }

    // -------------------------------------------------------------------
    // Test 2: supportsInterface still works for base hook
    // -------------------------------------------------------------------
    function test_supportsInterface() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        assertTrue(tiersHook.supportsInterface(type(IJB721TiersHook).interfaceId), "Should support IJB721TiersHook");
    }

    // -------------------------------------------------------------------
    // Test 3: Mint + manual delegate -> getVotes equals tier votingUnits
    // -------------------------------------------------------------------
    function test_mintAndDelegate_getVotes() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");

        // Mint an NFT to user (CHECKPOINTS already deployed during init).
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();

        // Without delegation, getVotes should be 0.
        assertEq(module.getVotes(user), 0, "Votes should be 0 before delegation");

        // User self-delegates.
        vm.prank(user);
        module.delegate(user);

        assertEq(module.getVotes(user), 100, "Votes should be 100 after delegation");
    }

    // -------------------------------------------------------------------
    // Test 4: No auto-delegation — delegates(user) stays address(0) after mint
    // -------------------------------------------------------------------
    function test_noAutoDelegation_delegateStaysZero() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");

        // Mint an NFT to user (CHECKPOINTS already deployed during init).
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();

        // Delegate should be address(0) — no auto-delegation.
        assertEq(module.delegates(user), address(0), "Delegate should be zero after mint");
    }

    // -------------------------------------------------------------------
    // Test 5: Transfer moves checkpointed votes (with manual delegation)
    // -------------------------------------------------------------------
    function test_transfer_movesCheckpointedVotes() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        // Mint to alice (CHECKPOINTS already deployed during init).
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, alice);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();

        // Both delegate to themselves.
        vm.prank(alice);
        module.delegate(alice);
        vm.prank(bob);
        module.delegate(bob);

        assertEq(module.getVotes(alice), 100, "Alice should have 100 votes");
        assertEq(module.getVotes(bob), 0, "Bob should have 0 votes");

        // Transfer NFT from alice to bob.
        uint256 tokenId = _generateTokenId(1, 1);
        vm.prank(alice);
        IERC721(address(tiersHook)).transferFrom(alice, bob, tokenId);

        assertEq(module.getVotes(alice), 0, "Alice should have 0 votes after transfer");
        assertEq(module.getVotes(bob), 100, "Bob should have 100 votes after transfer");
    }

    // -------------------------------------------------------------------
    // Test 6: getPastVotes / getPastTotalSupply checkpoints
    // -------------------------------------------------------------------
    function test_getPastVotes_checkpoint() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");

        // Mint first NFT to test checkpoint tracking.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();

        // User self-delegates so checkpoints are created going forward.
        vm.prank(user);
        module.delegate(user);

        uint256 blockBeforeSecondMint = block.number;
        vm.roll(block.number + 1);

        // Mint a second NFT.
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        uint256 blockAfterSecondMint = block.number;
        vm.roll(block.number + 1);

        // Past votes before second mint = 100 (from first NFT + delegation).
        assertEq(module.getPastVotes(user, blockBeforeSecondMint), 100, "Past votes before second mint should be 100");
        // Past votes after second mint = 200.
        assertEq(module.getPastVotes(user, blockAfterSecondMint), 200, "Past votes after second mint should be 200");

        // Past total supply.
        assertEq(
            module.getPastTotalSupply(blockBeforeSecondMint), 100, "Past total supply before second mint should be 100"
        );
        assertEq(
            module.getPastTotalSupply(blockAfterSecondMint), 200, "Past total supply after second mint should be 200"
        );
    }

    // -------------------------------------------------------------------
    // Test 7: Multi-tier with different voting units
    // -------------------------------------------------------------------
    function test_multiTier_differentVotingUnits() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(3);

        // Set custom voting units per tier.
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 1, 100);
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 2, 200);
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 3, 500);

        address user = makeAddr("user");

        // Mint one from tier 1 to test checkpoint tracking.
        uint16[] memory tier1 = new uint16[](1);
        tier1[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tier1, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();

        // User self-delegates.
        vm.prank(user);
        module.delegate(user);

        // Mint from remaining tiers.
        uint16[] memory tier2 = new uint16[](1);
        tier2[0] = 2;
        uint16[] memory tier3 = new uint16[](1);
        tier3[0] = 3;

        vm.startPrank(owner);
        tiersHook.mintFor(tier2, user);
        tiersHook.mintFor(tier3, user);
        vm.stopPrank();

        // 100 + 200 + 500 = 800.
        assertEq(module.getVotes(user), 800, "User should have 800 checkpointed votes");
    }

    // -------------------------------------------------------------------
    // Test 8: Burn decreases checkpointed total supply
    // -------------------------------------------------------------------
    function test_burn_decreasesTotalSupply() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");

        // Mint 2 NFTs (first one deploys CHECKPOINTS lazily).
        uint16[] memory tiersToMint = new uint16[](2);
        tiersToMint[0] = 1;
        tiersToMint[1] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();

        // User self-delegates.
        vm.prank(user);
        module.delegate(user);

        assertEq(module.getVotes(user), 200, "User should have 200 votes from 2 NFTs");

        uint256 blockBeforeBurn = block.number;
        vm.roll(block.number + 1);

        // Burn one NFT.
        uint256[] memory tokensToBurn = new uint256[](1);
        tokensToBurn[0] = _generateTokenId(1, 1);
        tiersHook.burn(tokensToBurn);

        assertEq(module.getVotes(user), 100, "User should have 100 votes after burning 1 NFT");

        vm.roll(block.number + 1);

        assertEq(module.getPastTotalSupply(blockBeforeBurn), 200, "Past total supply before burn should be 200");
    }

    // -------------------------------------------------------------------
    // Test 9: delegate(address, uint256[]) writes owner checkpoint
    // -------------------------------------------------------------------
    function test_delegateWithTokenIds_writesOwnerCheckpoint() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");

        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();
        uint256 tokenId = _generateTokenId(1, 1);

        // Before enrollment, ownerOfAt returns address(0).
        assertEq(module.ownerOfAt(tokenId, block.number), address(0), "Unenrolled token should return address(0)");

        uint256 enrollBlock = block.number;
        vm.roll(block.number + 1);

        // Enroll via delegate(address, uint256[]).
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        vm.prank(user);
        module.delegate(user, tokenIds);

        // ownerOfAt returns the owner for blocks >= enrollment.
        assertEq(module.ownerOfAt(tokenId, enrollBlock + 1), user, "Enrolled token should return owner");
    }

    // -------------------------------------------------------------------
    // Test 10: delegate(address, uint256[]) delegates voting power
    // -------------------------------------------------------------------
    function test_delegateWithTokenIds_delegates() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");
        address delegatee = makeAddr("delegatee");

        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();
        uint256 tokenId = _generateTokenId(1, 1);

        // Delegatee self-delegates first so they can receive.
        vm.prank(delegatee);
        module.delegate(delegatee);

        // Enroll and delegate to a different address.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        vm.prank(user);
        module.delegate(delegatee, tokenIds);

        assertEq(module.delegates(user), delegatee, "Should delegate to specified delegatee");
        assertEq(module.getVotes(delegatee), 100, "Delegatee should have user's votes");
    }

    // -------------------------------------------------------------------
    // Test 11: delegate(address, uint256[]) reverts for non-owner
    // -------------------------------------------------------------------
    function test_delegateWithTokenIds_revertsForNonOwner() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");
        address attacker = makeAddr("attacker");

        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();
        uint256 tokenId = _generateTokenId(1, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.expectRevert(
            abi.encodeWithSelector(JB721Checkpoints.JB721Checkpoints_NotOwner.selector, tokenId, attacker)
        );
        vm.prank(attacker);
        module.delegate(attacker, tokenIds);
    }

    // -------------------------------------------------------------------
    // Test 12: delegate(address, uint256[]) is idempotent for checkpoints
    // -------------------------------------------------------------------
    function test_delegateWithTokenIds_idempotentCheckpoints() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");

        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();
        uint256 tokenId = _generateTokenId(1, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        // Enroll once.
        vm.prank(user);
        module.delegate(user, tokenIds);

        uint256 enrollBlock = block.number;
        vm.roll(block.number + 10);

        // Enroll again — should not write a duplicate checkpoint.
        vm.prank(user);
        module.delegate(user, tokenIds);

        // ownerOfAt at the enrollment block should still return user (first checkpoint).
        assertEq(module.ownerOfAt(tokenId, enrollBlock), user, "First enrollment checkpoint should persist");
        assertEq(module.ownerOfAt(tokenId, block.number), user, "Current block should return user");
    }

    // -------------------------------------------------------------------
    // Test 13: ownerOfAt returns address(0) for unenrolled token
    // -------------------------------------------------------------------
    function test_ownerOfAt_returnsZeroForUnenrolledToken() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");

        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();
        uint256 tokenId = _generateTokenId(1, 1);

        // Never enrolled, never transferred — ownerOfAt should return address(0).
        assertEq(module.ownerOfAt(tokenId, block.number), address(0), "Unenrolled token should return address(0)");
    }

    // -------------------------------------------------------------------
    // Test 14: ownerOfAt returns address(0) before enrollment block
    // -------------------------------------------------------------------
    function test_ownerOfAt_returnsZeroBeforeEnrollmentBlock() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");

        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();
        uint256 tokenId = _generateTokenId(1, 1);

        uint256 blockBeforeEnroll = block.number;
        vm.roll(block.number + 5);

        // Enroll at block + 5.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        vm.prank(user);
        module.delegate(user, tokenIds);

        // Querying before enrollment block returns address(0).
        assertEq(
            module.ownerOfAt(tokenId, blockBeforeEnroll),
            address(0),
            "ownerOfAt before enrollment should return address(0)"
        );

        // Querying at/after enrollment block returns owner.
        assertEq(module.ownerOfAt(tokenId, block.number), user, "ownerOfAt at enrollment block should return owner");
    }

    // -------------------------------------------------------------------
    // Test 15: Transferred tokens still eligible without explicit enrollment
    // -------------------------------------------------------------------
    function test_ownerOfAt_worksForTransferredTokens() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, alice);

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();
        uint256 tokenId = _generateTokenId(1, 1);

        // Before transfer — unenrolled, returns address(0).
        assertEq(module.ownerOfAt(tokenId, block.number), address(0), "Before transfer should return address(0)");

        vm.roll(block.number + 1);

        // Transfer writes a checkpoint via onTransfer (from != address(0)).
        vm.prank(alice);
        IERC721(address(tiersHook)).transferFrom(alice, bob, tokenId);

        // After transfer — checkpoint exists, bob is the owner.
        assertEq(module.ownerOfAt(tokenId, block.number), bob, "After transfer should return bob");
    }

    // -------------------------------------------------------------------
    // Test 16: Unauthorized onTransfer reverts
    // -------------------------------------------------------------------
    function test_unauthorizedOnTransfer_reverts() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        // Mint to test checkpoint tracking.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, makeAddr("user"));

        IJB721Checkpoints module = tiersHook.CHECKPOINTS();

        vm.expectRevert(
            abi.encodeWithSelector(
                JB721Checkpoints.JB721Checkpoints_Unauthorized.selector, address(this), address(tiersHook)
            )
        );
        module.onTransfer(address(0), address(1), 1);
    }
}
