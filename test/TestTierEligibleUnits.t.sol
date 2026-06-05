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

/// @title TestTierEligibleUnits
/// @notice Tests the per-tier owner-tracked voting-units checkpoint trace: it increments on mint, stays stable across
/// transfers, and decrements on burn.
contract TestTierEligibleUnits is UnitTestSetup {
    /// @notice Deploys a ForTest hook with the given number of tiers and `useVotingUnits` enabled.
    function _initializeHook(uint256 numberOfTiers) internal returns (ForTest_JB721TiersHook tiersHook) {
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

    /// @notice Helper to mint one NFT of `tier` to `to`.
    function _mint(ForTest_JB721TiersHook tiersHook, uint16 tier, address to) internal {
        uint16[] memory tiers = new uint16[](1);
        tiers[0] = tier;
        vm.prank(owner);
        tiersHook.mintFor(tiers, to);
    }

    /// @notice Helper to backfill a single token for `account`.
    function _backfill(IJB721Checkpoints module, address account, uint256 tokenId) internal {
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        vm.prank(account);
        module.delegate(account, ids);
    }

    // -------------------------------------------------------------------
    // Mint increments; backfill is idempotent.
    // -------------------------------------------------------------------
    function test_mintIncrements_backfillIsIdempotent() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHook(1);
        address alice = makeAddr("alice");

        uint256 beforeMintBlock = block.number;
        vm.roll(block.number + 1);

        _mint(tiersHook, 1, alice);
        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        uint256 mintBlock = block.number;
        vm.roll(block.number + 1);

        // Mint writes the tier's owner-tracked voting units.
        assertEq(module.getPastTierVotingUnits(1, beforeMintBlock), 0, "history before mint should be 0");
        assertEq(module.getPastTierVotingUnits(1, mintBlock), 100, "mint should add tier units");

        // Backfill cannot double-count a token that already has a mint checkpoint.
        _backfill(module, alice, tokenId);
        uint256 backfillBlock = block.number;
        vm.roll(block.number + 1);

        assertEq(module.getPastTierVotingUnits(1, backfillBlock), 100, "backfill should not double-count");
    }

    // -------------------------------------------------------------------
    // Transfer keeps the owner-tracked tier total stable.
    // -------------------------------------------------------------------
    function test_transferKeepsTierTotalStable() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHook(1);
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        _mint(tiersHook, 1, alice);
        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        uint256 mintBlock = block.number;
        vm.roll(block.number + 1);
        assertEq(module.getPastTierVotingUnits(1, mintBlock), 100, "mint should add tier units");

        vm.prank(alice);
        IERC721(address(tiersHook)).transferFrom(alice, bob, tokenId);
        uint256 transferBlock = block.number;
        vm.roll(block.number + 1);

        assertEq(module.getPastTierVotingUnits(1, transferBlock), 100, "transfer should keep tier total stable");

        // A second transfer does not change the owner-tracked tier total either.
        vm.prank(bob);
        IERC721(address(tiersHook)).transferFrom(bob, alice, tokenId);
        uint256 secondTransferBlock = block.number;
        vm.roll(block.number + 1);
        assertEq(module.getPastTierVotingUnits(1, secondTransferBlock), 100, "second transfer should not change total");
    }

    // -------------------------------------------------------------------
    // Burn of an eligible token decrements.
    // -------------------------------------------------------------------
    function test_burnDecrements() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHook(1);
        address alice = makeAddr("alice");

        _mint(tiersHook, 1, alice);
        _mint(tiersHook, 1, alice);
        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId1 = _generateTokenId(1, 1);

        uint256 mintedBlock = block.number;
        vm.roll(block.number + 1);
        assertEq(module.getPastTierVotingUnits(1, mintedBlock), 200, "two minted tokens = 200");

        // Burn one owner-tracked token.
        uint256[] memory toBurn = new uint256[](1);
        toBurn[0] = tokenId1;
        tiersHook.burn(toBurn);
        uint256 burnBlock = block.number;
        vm.roll(block.number + 1);

        assertEq(module.getPastTierVotingUnits(1, burnBlock), 100, "burn should remove one token's units");
    }

    // -------------------------------------------------------------------
    // Re-enroll is idempotent (no double count).
    // -------------------------------------------------------------------
    function test_reEnrollDoesNotDoubleCount() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHook(1);
        address alice = makeAddr("alice");

        _mint(tiersHook, 1, alice);
        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        _backfill(module, alice, tokenId);
        vm.roll(block.number + 5);
        _backfill(module, alice, tokenId); // second backfill
        uint256 b = block.number;
        vm.roll(block.number + 1);

        assertEq(module.getPastTierVotingUnits(1, b), 100, "backfill must not double count");
    }

    // -------------------------------------------------------------------
    // Current/future block lookups match Votes.getPastTotalSupply semantics.
    // -------------------------------------------------------------------
    function test_getPastTierVotingUnits_revertsForCurrentBlock() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHook(1);
        address alice = makeAddr("alice");

        _mint(tiersHook, 1, alice);
        IJB721Checkpoints module = tiersHook.checkpoints();
        _backfill(module, alice, _generateTokenId(1, 1));

        vm.expectRevert();
        module.getPastTierVotingUnits(1, block.number);
    }

    // -------------------------------------------------------------------
    // mint -> transfer -> burn nets to zero.
    // -------------------------------------------------------------------
    function test_mintTransferBurnNetsZero() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHook(1);
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        _mint(tiersHook, 1, alice);
        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        vm.roll(block.number + 1);
        vm.prank(alice);
        IERC721(address(tiersHook)).transferFrom(alice, bob, tokenId); // total remains 100
        vm.roll(block.number + 1);

        uint256[] memory toBurn = new uint256[](1);
        toBurn[0] = tokenId;
        tiersHook.burn(toBurn); // total becomes 0
        uint256 b = block.number;
        vm.roll(block.number + 1);

        assertEq(module.getPastTierVotingUnits(1, b), 0, "mint->transfer->burn nets zero");
    }

    // -------------------------------------------------------------------
    // A minted-then-burned token returns the trace to zero.
    // -------------------------------------------------------------------
    function test_mintThenBurnRemovesUnits() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;
        defaultTierConfig.votingUnits = 100;

        ForTest_JB721TiersHook tiersHook = _initializeHook(1);
        address alice = makeAddr("alice");

        _mint(tiersHook, 1, alice);
        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 tokenId = _generateTokenId(1, 1);

        uint256 mintBlock = block.number;
        vm.roll(block.number + 1);
        assertEq(module.getPastTierVotingUnits(1, mintBlock), 100, "mint should add tier units");

        uint256[] memory toBurn = new uint256[](1);
        toBurn[0] = tokenId;
        tiersHook.burn(toBurn);
        uint256 b = block.number;
        vm.roll(block.number + 1);

        assertEq(module.getPastTierVotingUnits(1, b), 0, "burn should remove minted token units");
    }

    // -------------------------------------------------------------------
    // Tiers are tracked independently.
    // -------------------------------------------------------------------
    function test_tiersTrackedIndependently() public {
        defaultTierConfig.flags.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        defaultTierConfig.flags.useVotingUnits = true;

        ForTest_JB721TiersHook tiersHook = _initializeHook(3);
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 1, 100);
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 2, 200);
        tiersHook.test_store().ForTest_setTierVotingUnits(address(tiersHook), 3, 500);

        address alice = makeAddr("alice");
        _mint(tiersHook, 1, alice);
        _mint(tiersHook, 2, alice);
        _mint(tiersHook, 3, alice);

        IJB721Checkpoints module = tiersHook.checkpoints();
        uint256 b = block.number;
        vm.roll(block.number + 1);

        assertEq(module.getPastTierVotingUnits(1, b), 100, "tier 1 = 100");
        assertEq(module.getPastTierVotingUnits(2, b), 200, "tier 2 = 200");
        assertEq(module.getPastTierVotingUnits(3, b), 500, "tier 3 = 500");
    }
}
