// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {JB721TiersHookStore} from "../../../src/JB721TiersHookStore.sol";
import {JB721TierConfig} from "../../../src/structs/JB721TierConfig.sol";
import {JB721TiersHookFlags} from "../../../src/structs/JB721TiersHookFlags.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

/// @notice Handler for JB721TiersHookStore invariant tests.
/// @dev Acts as the "hook" address itself, so msg.sender (this) == hook in the store.
contract TierStoreHandler is CommonBase, StdCheats, StdUtils {
    JB721TiersHookStore public immutable STORE;

    // This contract acts as the hook.
    address public HOOK;

    // Ghost variable tracking the max tier ID seen.
    uint256 public lowestMaxTierIdSeen;

    // Track how many tiers we've added.
    uint256 public tiersAdded;

    // Track minted token IDs so we can only burn minted tokens.
    uint256[] public mintedTokenIds;

    // Track burned token IDs to avoid double-burn.
    mapping(uint256 => bool) public wasBurned;

    constructor(JB721TiersHookStore store) {
        STORE = store;
        HOOK = address(this);
    }

    /// @notice Add a new tier.
    function addTier(uint104 price, uint32 initialSupply, uint16 reserveFrequency, uint24 category) public {
        // Bound inputs to valid ranges.
        initialSupply = uint32(bound(initialSupply, 1, 1_000_000));
        price = uint104(bound(price, 1, type(uint104).max));
        category = uint24(bound(category, 0, 100));

        // Reserve frequency must be <= initialSupply if non-zero.
        if (reserveFrequency > 0) {
            reserveFrequency = uint16(bound(reserveFrequency, 1, 200));
        }

        JB721TierConfig[] memory configs = new JB721TierConfig[](1);
        configs[0] = JB721TierConfig({
            price: price,
            initialSupply: initialSupply,
            votingUnits: 0,
            reserveFrequency: reserveFrequency,
            reserveBeneficiary: address(0),
            encodedIPFSUri: bytes32(0),
            category: category,
            discountPercent: 0,
            allowOwnerMint: true,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        try this._doAddTiers(configs) {
            tiersAdded++;
            _updateMaxTierIdSeen();
        } catch {}
    }

    /// @dev External wrapper so calldata encoding is correct for the store.
    function _doAddTiers(JB721TierConfig[] calldata configs) external {
        STORE.recordAddTiers(configs);
    }

    /// @notice Remove a tier.
    function removeTier(uint256 tierId) public {
        uint256 maxId = STORE.maxTierIdOf(HOOK);
        if (maxId == 0) return;

        tierId = bound(tierId, 1, maxId);

        uint256[] memory ids = new uint256[](1);
        ids[0] = tierId;

        try this._doRemoveTiers(ids) {} catch {}
    }

    /// @dev External wrapper for calldata.
    function _doRemoveTiers(uint256[] calldata ids) external {
        STORE.recordRemoveTierIds(ids);
    }

    /// @notice Mint from a tier (simulates store recording a mint).
    function mint(uint256 tierId) public {
        uint256 maxId = STORE.maxTierIdOf(HOOK);
        if (maxId == 0) return;

        tierId = bound(tierId, 1, maxId);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = uint16(tierId);

        try this._doMint(type(uint256).max, tierIds) returns (uint256[] memory tokenIds) {
            for (uint256 i; i < tokenIds.length; i++) {
                if (tokenIds[i] != 0) {
                    mintedTokenIds.push(tokenIds[i]);
                }
            }
        } catch {}

        _updateMaxTierIdSeen();
    }

    /// @dev External wrapper for calldata.
    function _doMint(uint256 amount, uint16[] calldata tierIds) external returns (uint256[] memory tokenIds) {
        (tokenIds,) = STORE.recordMint(amount, tierIds, true);
    }

    /// @notice Burn a minted token.
    function burn(uint256 indexSeed) public {
        if (mintedTokenIds.length == 0) return;

        uint256 index = bound(indexSeed, 0, mintedTokenIds.length - 1);
        uint256 tokenId = mintedTokenIds[index];

        // Skip if already burned.
        if (wasBurned[tokenId]) return;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        try this._doBurn(tokenIds) {
            wasBurned[tokenId] = true;
        } catch {}
    }

    /// @dev External wrapper for calldata.
    function _doBurn(uint256[] calldata tokenIds) external {
        STORE.recordBurn(tokenIds);
    }

    function mintedTokenCount() external view returns (uint256) {
        return mintedTokenIds.length;
    }

    function _updateMaxTierIdSeen() internal {
        uint256 current = STORE.maxTierIdOf(HOOK);
        if (lowestMaxTierIdSeen == 0 || current > lowestMaxTierIdSeen) {
            lowestMaxTierIdSeen = current;
        }
    }
}
