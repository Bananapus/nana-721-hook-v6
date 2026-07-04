// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {JBBitmap} from "../../src/libraries/JBBitmap.sol";
import {JBBitmapWord} from "../../src/structs/JBBitmapWord.sol";

/// @notice Small Halmos entrypoints for the tier-removal bitmap used by `JB721TiersHookStore`.
/// @dev These proofs keep symbolic domains bounded so the CI lane can catch bit-index regressions quickly.
contract JBBitmapHalmos {
    using JBBitmap for mapping(uint256 => uint256);
    using JBBitmap for JBBitmapWord;

    mapping(uint256 => uint256) internal _bitmap;

    /// @notice Proves `removeTier` makes the selected tier read as removed.
    /// @param index The tier ID to remove, bounded to the first 256 bitmap words for solver speed.
    function check_removeTierRoundTrip(uint16 index) public {
        _bitmap.removeTier(index);

        assert(_bitmap.isTierIdRemoved(index));
    }

    /// @notice Proves `removeTier` is one-way and idempotent for an already removed tier.
    /// @param index The tier ID to remove twice, bounded to the first 256 bitmap words for solver speed.
    function check_removeTierIdempotent(uint16 index) public {
        _bitmap.removeTier(index);
        uint256 wordAfterFirstRemoval = _bitmap.readId(index).currentWord;

        _bitmap.removeTier(index);

        assert(_bitmap.isTierIdRemoved(index));
        assert(_bitmap.readId(index).currentWord == wordAfterFirstRemoval);
    }

    /// @notice Proves removing one tier does not remove a different tier in the same bitmap word.
    /// @param depth The bitmap word to test.
    /// @param bitA The bit to remove.
    /// @param bitB A different bit in the same word, which must remain active.
    function check_removeTierDoesNotAffectSameWordNeighbor(uint8 depth, uint8 bitA, uint8 bitB) public {
        if (bitA == bitB) return;

        uint256 indexA = (uint256(depth) << 8) | uint256(bitA);
        uint256 indexB = (uint256(depth) << 8) | uint256(bitB);

        _bitmap.removeTier(indexA);

        assert(_bitmap.isTierIdRemoved(indexA));
        assert(!_bitmap.isTierIdRemoved(indexB));
        assert(_bitmap.readId(indexA).currentWord == uint256(1) << bitA);
    }

    /// @notice Proves a cached bitmap word only needs refreshing when the requested tier is in another word.
    /// @param indexA The tier ID used to read the cached bitmap word.
    /// @param indexB The tier ID later checked against the cached word.
    function check_refreshBitmapNeededMatchesDepthChange(uint16 indexA, uint16 indexB) public view {
        JBBitmapWord memory word = _bitmap.readId(indexA);

        assert(word.refreshBitmapNeeded(indexB) == ((uint256(indexA) >> 8) != (uint256(indexB) >> 8)));
    }

    /// @notice Proves `clearId` is the exact inverse of `removeTier`: clearing a removed tier makes it active again,
    ///         restoring the bitmap word to zero. `removeTier` is documented as one-way, but `clearId` exists as the
    ///         reactivation path, and this proves the two round-trip cleanly for any tier.
    /// @param index The tier ID to remove and then clear, bounded to the first 256 bitmap words for solver speed.
    function check_clearIdReversesRemoveTier(uint16 index) public {
        _bitmap.removeTier(index);
        assert(_bitmap.isTierIdRemoved(index));

        _bitmap.clearId(index);

        assert(!_bitmap.isTierIdRemoved(index));
        assert(_bitmap.readId(index).currentWord == 0);
    }

    /// @notice Proves removing one tier does not affect a tier in a DIFFERENT bitmap word (different depth). The
    ///         existing neighbor proof only covers bits sharing one word; this proves the mapping-keyed words never
    ///         collide across depths, so a removal in one word can never flip a bit in another.
    /// @param depthA The bitmap word holding the removed tier.
    /// @param depthB A different bitmap word whose tier must remain active.
    /// @param bit The bit offset used within each word.
    function check_removeTierDoesNotAffectOtherWord(uint8 depthA, uint8 depthB, uint8 bit) public {
        if (depthA == depthB) return;

        uint256 indexA = (uint256(depthA) << 8) | uint256(bit);
        uint256 indexB = (uint256(depthB) << 8) | uint256(bit);

        _bitmap.removeTier(indexA);

        assert(_bitmap.isTierIdRemoved(indexA));
        assert(!_bitmap.isTierIdRemoved(indexB));
    }
}
