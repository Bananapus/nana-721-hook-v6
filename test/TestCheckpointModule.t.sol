// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./utils/UnitTestSetup.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "./utils/ForTest_JB721TiersHook.sol";
import {JB721CheckpointModule} from "../src/JB721CheckpointModule.sol";
import {IJB721CheckpointModule} from "../src/interfaces/IJB721CheckpointModule.sol";
import {IJB721TiersHook} from "../src/interfaces/IJB721TiersHook.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title TestCheckpointModule
/// @notice Tests the checkpoint module IVotes checkpointed voting power baked into the base hook:
/// delegation, checkpoints, transfer, multi-tier, burn, and module deployment.
contract TestCheckpointModule is UnitTestSetup {
    /// @notice Deploys a ForTest hook with the given number of tiers.
    function _initializeHookWithCheckpoints(
        uint256 numberOfTiers
    )
        internal
        returns (ForTest_JB721TiersHook tiersHook)
    {
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
    // Test 1: Checkpoint module is deployed during initialization
    // -------------------------------------------------------------------
    function test_checkpointModule_isDeployed() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        assertTrue(address(tiersHook.CHECKPOINT_MODULE()) != address(0), "Checkpoint module should be deployed");
    }

    // -------------------------------------------------------------------
    // Test 2: supportsInterface still works for base hook
    // -------------------------------------------------------------------
    function test_supportsInterface() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);

        assertTrue(
            tiersHook.supportsInterface(type(IJB721TiersHook).interfaceId), "Should support IJB721TiersHook"
        );
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
        IJB721CheckpointModule module = tiersHook.CHECKPOINT_MODULE();

        address user = makeAddr("user");

        // Mint an NFT to user.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

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
        IJB721CheckpointModule module = tiersHook.CHECKPOINT_MODULE();

        address user = makeAddr("user");

        assertEq(module.delegates(user), address(0), "Delegate should be zero before mint");

        // Mint an NFT to user.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        // Delegate should remain address(0) — no auto-delegation.
        assertEq(module.delegates(user), address(0), "Delegate should still be zero after mint");
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
        IJB721CheckpointModule module = tiersHook.CHECKPOINT_MODULE();

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        // Mint to alice.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, alice);

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
        IJB721CheckpointModule module = tiersHook.CHECKPOINT_MODULE();

        address user = makeAddr("user");

        // User self-delegates before mint so checkpoints are created.
        vm.prank(user);
        module.delegate(user);

        uint256 blockBeforeMint = block.number;
        vm.roll(block.number + 1);

        // Mint.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

        uint256 blockAfterMint = block.number;
        vm.roll(block.number + 1);

        // Past votes before mint = 0.
        assertEq(module.getPastVotes(user, blockBeforeMint), 0, "Past votes before mint should be 0");
        // Past votes after mint = 100.
        assertEq(module.getPastVotes(user, blockAfterMint), 100, "Past votes after mint should be 100");

        // Past total supply.
        assertEq(module.getPastTotalSupply(blockBeforeMint), 0, "Past total supply before mint should be 0");
        assertEq(module.getPastTotalSupply(blockAfterMint), 100, "Past total supply after mint should be 100");
    }

    // -------------------------------------------------------------------
    // Test 7: Multi-tier with different voting units
    // -------------------------------------------------------------------
    function test_multiTier_differentVotingUnits() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(3);
        IJB721CheckpointModule module = tiersHook.CHECKPOINT_MODULE();

        // Set custom voting units per tier.
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 1, 100);
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 2, 200);
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 3, 500);

        address user = makeAddr("user");

        // User self-delegates before mints.
        vm.prank(user);
        module.delegate(user);

        // Mint one from each tier.
        uint16[] memory tier1 = new uint16[](1);
        tier1[0] = 1;
        uint16[] memory tier2 = new uint16[](1);
        tier2[0] = 2;
        uint16[] memory tier3 = new uint16[](1);
        tier3[0] = 3;

        vm.startPrank(owner);
        tiersHook.mintFor(tier1, user);
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
        IJB721CheckpointModule module = tiersHook.CHECKPOINT_MODULE();

        address user = makeAddr("user");

        // User self-delegates before mints.
        vm.prank(user);
        module.delegate(user);

        // Mint 2 NFTs.
        uint16[] memory tiersToMint = new uint16[](2);
        tiersToMint[0] = 1;
        tiersToMint[1] = 1;
        vm.prank(owner);
        tiersHook.mintFor(tiersToMint, user);

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
    // Test 9: Unauthorized onTransfer reverts
    // -------------------------------------------------------------------
    function test_unauthorizedOnTransfer_reverts() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook tiersHook = _initializeHookWithCheckpoints(1);
        IJB721CheckpointModule module = tiersHook.CHECKPOINT_MODULE();

        vm.expectRevert(JB721CheckpointModule.JB721CheckpointModule_Unauthorized.selector);
        module.onTransfer(address(0), address(1), 1);
    }
}
