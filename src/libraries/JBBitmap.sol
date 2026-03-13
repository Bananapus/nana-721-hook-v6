// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {JBBitmapWord} from "../structs/JBBitmapWord.sol";

/// @title JBBitmap
/// @notice Utilities to manage a bool bitmap. Used for storing inactive tiers.
library JBBitmap {
    /// @notice Initialize a `JBBitmapWord` struct based on a mapping storage pointer and an index.
    function readId(
        mapping(uint256 => uint256) storage self,
        uint256 index
    )
        internal
        view
        returns (JBBitmapWord memory)
    {
        uint256 depth = _retrieveDepth(index);

        return JBBitmapWord({currentWord: self[depth], currentDepth: depth});
    }

    /// @notice Get the status of the specified bit within the `JBBitmapWord` struct.
    /// @dev The `index` is the index that the bit would have if the bitmap were reshaped to a 1*n matrix.
    /// @return The boolean value at the specified index, which indicates whether the corresponding tier has been
    /// removed.
    function isTierIdRemoved(JBBitmapWord memory self, uint256 index) internal pure returns (bool) {
        return (self.currentWord >> (index % 256)) & 1 == 1;
    }

    /// @notice Get the status of the specified bit within the `JBBitmapWord` struct.
    /// @dev The `index` is the index that the bit would have if the bitmap were reshaped to a 1*n matrix.
    function isTierIdRemoved(mapping(uint256 => uint256) storage self, uint256 index) internal view returns (bool) {
        uint256 depth = _retrieveDepth(index);
        return isTierIdRemoved(JBBitmapWord({currentWord: self[depth], currentDepth: depth}), index);
    }

    /// @notice Set the bit at the given index to true, indicating that the corresponding tier has been removed.
    /// @dev This is a one-way operation.
    function removeTier(mapping(uint256 => uint256) storage self, uint256 index) internal {
        uint256 depth = _retrieveDepth(index);
        // forge-lint: disable-next-line(incorrect-shift)
        self[depth] |= uint256(1 << (index % 256));
    }

    /// @notice Check if the specified index is at a different depth than the current depth of the `JBBitmapWord`
    /// struct.
    /// @dev If the depth is different, the bitmap's current depth needs to be updated.
    /// @return Whether the bitmap needs to be refreshed.
    function refreshBitmapNeeded(JBBitmapWord memory self, uint256 index) internal pure returns (bool) {
        return _retrieveDepth(index) != self.currentDepth;
    }

    /// @notice Return the line number (depth) of a given index within the bitmap matrix.
    function _retrieveDepth(uint256 index) internal pure returns (uint256) {
        return index >> 8; // div by 256
    }
}
