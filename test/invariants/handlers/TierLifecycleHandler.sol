// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../../src/JB721TiersHook.sol";
import "../../../src/JB721TiersHookStore.sol";
import "../../../src/structs/JB721TierConfig.sol";
import "../../../src/structs/JB721Tier.sol";
import "../../../src/interfaces/IJB721TiersHookStore.sol";
import "@bananapus/core-v6/src/libraries/JBConstants.sol";
import "@bananapus/core-v6/src/structs/JBAfterPayRecordedContext.sol";
import "@bananapus/core-v6/src/structs/JBTokenAmount.sol";

/// @title TierLifecycleHandler
/// @notice Handler for 721 tier lifecycle invariant testing.
///         8 operations: payAndMintNFT, cashOutNFT, addTier, removeTier,
///         mintReserves, setDiscount, ownerMint, advanceTime.
contract TierLifecycleHandler is Test {
    JB721TiersHook public hook;
    JB721TiersHookStore public store;
    address public hookAddress;
    address public owner;
    address public mockController;

    uint256 public constant PROJECT_ID = 69;
    uint256 public constant NUM_ACTORS = 5;
    address[] public actors;

    // Ghost variables for supply tracking
    mapping(uint256 => uint256) public ghost_mintedPerTier; // tierId => minted count
    mapping(uint256 => uint256) public ghost_burnedPerTier; // tierId => burned count
    mapping(uint256 => uint256) public ghost_reservesMintedPerTier; // tierId => reserves minted
    uint256 public ghost_totalPayCredits;
    mapping(address => uint256) public ghost_actorCredits; // actor => credit balance
    uint256 public ghost_tiersAdded;
    uint256 public ghost_tiersRemoved;

    // Track token IDs per actor for cash outs
    mapping(address => uint256[]) internal _actorTokenIds;

    // Track removed tier IDs
    mapping(uint256 => bool) public ghost_tierRemoved;

    // Operation counters
    uint256 public callCount_payAndMint;
    uint256 public callCount_cashOut;
    uint256 public callCount_addTier;
    uint256 public callCount_removeTier;
    uint256 public callCount_mintReserves;
    uint256 public callCount_setDiscount;
    uint256 public callCount_ownerMint;
    uint256 public callCount_advanceTime;

    constructor(JB721TiersHook _hook, JB721TiersHookStore _store, address _owner, address _mockController) {
        hook = _hook;
        store = _store;
        hookAddress = address(_hook);
        owner = _owner;
        mockController = _mockController;

        for (uint256 i = 0; i < NUM_ACTORS; i++) {
            address actor = address(uint160(0x6000 + i));
            actors.push(actor);
        }
    }

    function _getActor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @notice Simulate a payment that mints NFTs by directly calling store.recordMint.
    function payAndMintNFT(uint256 seed) external {
        address actor = _getActor(seed);

        // Get max tier ID to pick a valid tier
        uint256 maxTierId = store.maxTierIdOf(hookAddress);
        if (maxTierId == 0) return;

        // Pick a tier (1-indexed)
        uint256 tierId = (seed % maxTierId) + 1;

        // Check if tier is removed
        if (ghost_tierRemoved[tierId]) return;

        // Get tier info
        uint256[] memory categories = new uint256[](0);
        JB721Tier[] memory tierInfo = store.tiersOf(hookAddress, categories, false, 0, 100);

        // Find the target tier
        uint104 tierPrice = 0;
        for (uint256 i = 0; i < tierInfo.length; i++) {
            if (tierInfo[i].id == tierId) {
                tierPrice = tierInfo[i].price;
                break;
            }
        }
        if (tierPrice == 0) return;

        // Call recordMint as the hook
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = uint16(tierId);

        vm.prank(hookAddress);
        try store.recordMint(tierPrice, tierIds, false) returns (uint256[] memory tokenIds, uint256) {
            // Track minted tokens
            for (uint256 i = 0; i < tokenIds.length; i++) {
                _actorTokenIds[actor].push(tokenIds[i]);
            }
            ghost_mintedPerTier[tierId]++;
            callCount_payAndMint++;
        } catch {}
    }

    /// @notice Simulate a cash out by burning an NFT.
    function cashOutNFT(uint256 seed) external {
        address actor = _getActor(seed);

        // Check if actor has any tokens
        if (_actorTokenIds[actor].length == 0) return;

        // Pick a token to burn
        uint256 tokenIndex = seed % _actorTokenIds[actor].length;
        uint256 tokenId = _actorTokenIds[actor][tokenIndex];

        uint256 tierId = store.tierIdOfToken(tokenId);

        // Call recordBurn as the hook
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(hookAddress);
        try store.recordBurn(tokenIds) {
            ghost_burnedPerTier[tierId]++;

            // Remove token from actor's list (swap and pop)
            uint256 lastIndex = _actorTokenIds[actor].length - 1;
            if (tokenIndex != lastIndex) {
                _actorTokenIds[actor][tokenIndex] = _actorTokenIds[actor][lastIndex];
            }
            _actorTokenIds[actor].pop();

            callCount_cashOut++;
        } catch {}
    }

    /// @notice Add a new tier.
    function addTier(uint256 seed) external {
        uint256 price = bound(seed, 1, 1000);
        uint256 supply = bound(seed >> 8, 10, 500);

        JB721TierConfig[] memory newTiers = new JB721TierConfig[](1);
        newTiers[0] = JB721TierConfig({
            price: uint104(price),
            initialSupply: uint32(supply),
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32(0),
            category: uint24(100),
            discountPercent: 0,
            allowOwnerMint: true,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false
        });

        vm.prank(hookAddress);
        try store.recordAddTiers(newTiers) returns (uint256[] memory tierIds) {
            ghost_tiersAdded += tierIds.length;
            callCount_addTier++;
        } catch {}
    }

    /// @notice Remove a tier.
    function removeTier(uint256 seed) external {
        uint256 maxTierId = store.maxTierIdOf(hookAddress);
        if (maxTierId == 0) return;

        uint256 tierId = (seed % maxTierId) + 1;
        if (ghost_tierRemoved[tierId]) return;

        uint256[] memory tierIds = new uint256[](1);
        tierIds[0] = tierId;

        vm.prank(hookAddress);
        try store.recordRemoveTierIds(tierIds) {
            ghost_tierRemoved[tierId] = true;
            ghost_tiersRemoved++;
            callCount_removeTier++;
        } catch {}
    }

    /// @notice Mint reserves for a tier.
    function mintReserves(uint256 seed) external {
        uint256 maxTierId = store.maxTierIdOf(hookAddress);
        if (maxTierId == 0) return;

        uint256 tierId = (seed % maxTierId) + 1;
        if (ghost_tierRemoved[tierId]) return;

        // Try to mint 1 reserve
        vm.prank(hookAddress);
        try store.recordMintReservesFor(tierId, 1) returns (uint256[] memory tokenIds) {
            ghost_reservesMintedPerTier[tierId] += tokenIds.length;
            callCount_mintReserves++;
        } catch {}
    }

    /// @notice Set discount for a tier.
    function setDiscount(uint256 seed) external {
        uint256 maxTierId = store.maxTierIdOf(hookAddress);
        if (maxTierId == 0) return;

        uint256 tierId = (seed % maxTierId) + 1;
        uint256 discount = bound(seed >> 8, 0, 100); // 0-100%

        vm.prank(hookAddress);
        try store.recordSetDiscountPercentOf(tierId, discount) {
            callCount_setDiscount++;
        } catch {}
    }

    /// @notice Owner mint (direct mint with isOwnerMint=true).
    function ownerMint(uint256 seed) external {
        uint256 maxTierId = store.maxTierIdOf(hookAddress);
        if (maxTierId == 0) return;

        uint256 tierId = (seed % maxTierId) + 1;
        if (ghost_tierRemoved[tierId]) return;

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = uint16(tierId);

        vm.prank(hookAddress);
        try store.recordMint(0, tierIds, true) returns (uint256[] memory tokenIds, uint256) {
            address actor = _getActor(seed);
            for (uint256 i = 0; i < tokenIds.length; i++) {
                _actorTokenIds[actor].push(tokenIds[i]);
            }
            ghost_mintedPerTier[tierId]++;
            callCount_ownerMint++;
        } catch {}
    }

    /// @notice Advance time.
    function advanceTime(uint256 seed) external {
        uint256 delta = bound(seed, 1 hours, 30 days);
        vm.warp(block.timestamp + delta);
        callCount_advanceTime++;
    }

    // View helpers
    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function getActorTokenCount(address actor) external view returns (uint256) {
        return _actorTokenIds[actor].length;
    }
}
