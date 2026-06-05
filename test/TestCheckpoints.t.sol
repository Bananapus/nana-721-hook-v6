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

        // Checkpoints should not be deployed after initialization (lazy deployment).
        assertTrue(
            address(tiersHook.checkpoints()) == address(0),
            "Checkpoint module should not be deployed after initialization"
        );

        // Mint a token to trigger lazy deployment.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, owner);

        // Checkpoints should now be deployed after the first mint.
        assertTrue(
            address(tiersHook.checkpoints()) != address(0), "Checkpoint module should be deployed after first mint"
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

        // Mint an NFT to user (checkpoints already deployed during init).
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.checkpoints();

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

        // Mint an NFT to user (checkpoints already deployed during init).
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.checkpoints();

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

        // Mint to alice (checkpoints already deployed during init).
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, alice);

        IJB721Checkpoints module = tiersHook.checkpoints();

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

        IJB721Checkpoints module = tiersHook.checkpoints();

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

        IJB721Checkpoints module = tiersHook.checkpoints();

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

        // Mint 2 NFTs (the first one deploys checkpoints lazily).
        uint16[] memory tiersToMint = new uint16[](2);
        tiersToMint[0] = 1;
        tiersToMint[1] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.checkpoints();

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
    // Test 9: mint writes owner checkpoint
    // -------------------------------------------------------------------
    function test_mint_writesOwnerCheckpoint() public {
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

        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);
        uint256 mintBlock = block.number;
        vm.roll(block.number + 1);

        // Minting writes the initial owner checkpoint.
        assertEq(module.ownerOfAt(tokenId, mintBlock), user, "Minted token should return its initial owner");

        // Minting also tracks the tier's owner-based voting units.
        assertEq(module.getPastTierVotingUnits(1, mintBlock), 100, "Minted token should count in tier units");
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

        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        // Delegatee self-delegates first so they can receive.
        vm.prank(delegatee);
        module.delegate(delegatee);

        // Backfill if needed and delegate to a different address.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        vm.prank(user);
        module.delegate(delegatee, tokenIds);

        assertEq(module.delegates(user), delegatee, "Should delegate to specified delegatee");
        assertEq(module.getVotes(delegatee), 100, "Delegatee should have user's votes");
        assertEq(module.getTotalActiveVotes(), 100, "Active votes should include delegated voting units");
        assertEq(module.getTierActiveVotes(1), 100, "Tier active votes should include delegated voting units");
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

        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.expectRevert(abi.encodeWithSelector(JB721Checkpoints.JB721Checkpoints_NotOwner.selector, tokenId, attacker));
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

        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        // Backfill once.
        vm.prank(user);
        module.delegate(user, tokenIds);

        uint256 checkpointBlock = block.number;
        vm.roll(block.number + 10);

        // Backfill again — should not write a duplicate checkpoint.
        vm.prank(user);
        module.delegate(user, tokenIds);

        // ownerOfAt at the mint block should still return user (first checkpoint).
        assertEq(module.ownerOfAt(tokenId, checkpointBlock), user, "First owner checkpoint should persist");
        assertEq(module.ownerOfAt(tokenId, block.number), user, "Current block should return user");
    }

    // -------------------------------------------------------------------
    // Test 13: ownerOfAt returns the initial owner for a freshly minted token
    // -------------------------------------------------------------------
    function test_ownerOfAt_returnsMintOwnerForFreshToken() public {
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

        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        // Fresh mints are ownership-checkpointed immediately.
        assertEq(module.ownerOfAt(tokenId, block.number), user, "Minted token should return initial owner");
    }

    // -------------------------------------------------------------------
    // Test 14: ownerOfAt returns address(0) before mint block
    // -------------------------------------------------------------------
    function test_ownerOfAt_returnsZeroBeforeMintBlock() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address user = makeAddr("user");

        uint256 blockBeforeMint = block.number;
        vm.roll(block.number + 5);

        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        // Querying before mint returns address(0).
        assertEq(module.ownerOfAt(tokenId, blockBeforeMint), address(0), "ownerOfAt before mint should return zero");

        // Querying at/after mint returns owner.
        assertEq(module.ownerOfAt(tokenId, block.number), user, "ownerOfAt at mint block should return owner");
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

        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        // Before transfer — mint checkpoint records alice.
        assertEq(module.ownerOfAt(tokenId, block.number), alice, "Before transfer should return alice");

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

        IJB721Checkpoints module = tiersHook.checkpoints();

        vm.expectRevert(
            abi.encodeWithSelector(
                JB721Checkpoints.JB721Checkpoints_Unauthorized.selector, address(this), address(tiersHook)
            )
        );
        module.onTransfer(address(0), address(1), 1);
    }

    // -------------------------------------------------------------------
    // Test 17: Active votes follow delegated voting units through inactive custody
    // -------------------------------------------------------------------
    function test_activeVotes_inactiveRecipientThenDelegatedHolderAgain() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        address alice = makeAddr("alice");
        address amm = makeAddr("amm");

        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, alice);

        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        assertEq(module.getVotes(alice), 0, "Alice should have no votes before delegation");
        assertEq(module.getTotalActiveVotes(), 0, "Undelegated voting units should be inactive");

        uint256 inactiveBlock = block.number;
        vm.roll(block.number + 1);

        assertEq(module.getPastTotalSupply(inactiveBlock), 100, "Total supply should include undelegated voting units");
        assertEq(module.getPastTotalActiveVotes(inactiveBlock), 0, "Active total should exclude undelegated units");
        assertEq(
            module.getPastTierActiveVotes(1, inactiveBlock), 0, "Tier active total should exclude undelegated units"
        );

        vm.prank(alice);
        module.delegate(alice);

        assertEq(module.getVotes(alice), 100, "Alice should have votes after delegation");
        assertEq(module.getTotalActiveVotes(), 100, "Delegated voting units should be active");
        assertEq(module.getTierActiveVotes(1), 100, "Delegated voting units should be tier-active");

        uint256 activeBlock = block.number;
        vm.roll(block.number + 1);

        assertEq(module.getPastTotalActiveVotes(activeBlock), 100, "Active total should checkpoint delegation");
        assertEq(module.getPastTierActiveVotes(1, activeBlock), 100, "Tier active total should checkpoint delegation");

        vm.prank(alice);
        IERC721(address(tiersHook)).transferFrom(alice, amm, tokenId);

        assertEq(module.getVotes(alice), 0, "Alice should lose votes while token is in inactive custody");
        assertEq(module.getVotes(amm), 0, "Inactive custodian should not receive votes");
        assertEq(module.getTotalActiveVotes(), 0, "Inactive custody should remove voting units from active total");
        assertEq(module.getTierActiveVotes(1), 0, "Inactive custody should remove units from tier active total");

        uint256 inactiveCustodyBlock = block.number;
        vm.roll(block.number + 1);

        assertEq(
            module.getPastTotalActiveVotes(inactiveCustodyBlock), 0, "Active total should checkpoint inactive custody"
        );
        assertEq(
            module.getPastTierActiveVotes(1, inactiveCustodyBlock),
            0,
            "Tier active total should checkpoint inactive custody"
        );

        vm.prank(amm);
        IERC721(address(tiersHook)).transferFrom(amm, alice, tokenId);

        assertEq(module.getVotes(alice), 100, "Alice should regain votes when token returns");
        assertEq(module.getTotalActiveVotes(), 100, "Delegated holder should make returned voting units active again");
        assertEq(module.getTierActiveVotes(1), 100, "Returned token should become tier-active again");
    }

    // -------------------------------------------------------------------
    // Test 18: Tier active votes track delegation across multiple tiers
    // -------------------------------------------------------------------
    function test_tierActiveVotes_followDelegationAcrossTiers() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(3);

        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 1, 100);
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 2, 200);
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 3, 500);

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        uint16[] memory aliceTiers = new uint16[](2);
        aliceTiers[0] = 1;
        aliceTiers[1] = 2;

        uint16[] memory bobTiers = new uint16[](1);
        bobTiers[0] = 3;

        vm.startPrank(owner);
        tiersHook.mintFor(aliceTiers, alice);
        tiersHook.mintFor(bobTiers, bob);
        vm.stopPrank();

        IJB721Checkpoints module = tiersHook.checkpoints();

        vm.prank(alice);
        module.delegate(alice);

        assertEq(module.getTotalActiveVotes(), 300, "Alice's delegated tiers should set the active total");
        assertEq(module.getTierActiveVotes(1), 100, "Tier 1 should include Alice's delegated units");
        assertEq(module.getTierActiveVotes(2), 200, "Tier 2 should include Alice's delegated units");
        assertEq(module.getTierActiveVotes(3), 0, "Tier 3 should exclude undelegated Bob units");

        uint256 activeBlock = block.number;
        vm.roll(block.number + 1);

        assertEq(module.getPastTierActiveVotes(1, activeBlock), 100, "Past tier 1 active units should be checkpointed");
        assertEq(module.getPastTierActiveVotes(2, activeBlock), 200, "Past tier 2 active units should be checkpointed");
        assertEq(module.getPastTierActiveVotes(3, activeBlock), 0, "Past tier 3 active units should be zero");

        vm.prank(alice);
        module.delegate(address(0));

        assertEq(module.getTotalActiveVotes(), 0, "Clearing delegation should remove active total");
        assertEq(module.getTierActiveVotes(1), 0, "Clearing delegation should remove tier 1 active units");
        assertEq(module.getTierActiveVotes(2), 0, "Clearing delegation should remove tier 2 active units");
        assertEq(module.getTierActiveVotes(3), 0, "Clearing delegation should leave tier 3 inactive");
    }
}
