// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {JBBitmapWord} from "../structs/JBBitmapWord.sol";

/// @title JBBitmap
/// @notice Utilities to manage a bool bitmap. Used for storing inactive tiers.
library JBBitmap {
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
        return isTierIdRemoved({self: JBBitmapWord({currentWord: self[depth], currentDepth: depth}), index: index});
    }

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

    /// @notice Check if the specified index is at a different depth than the current depth of the `JBBitmapWord`
    /// struct.
    /// @dev If the depth is different, the bitmap's current depth needs to be updated.
    /// @return Whether the bitmap needs to be refreshed.
    function refreshBitmapNeeded(JBBitmapWord memory self, uint256 index) internal pure returns (bool) {
        return _retrieveDepth(index) != self.currentDepth;
    }

    /// @notice Clear the bit at the given index.
    /// @param self The bitmap to clear the bit from.
    /// @param index The index of the bit to clear.
    function clearId(mapping(uint256 => uint256) storage self, uint256 index) internal {
        self[_retrieveDepth(index)] &= ~_retrieveBitMask(index);
    }

    /// @notice Set the bit at the given index to true, indicating that the corresponding tier has been removed.
    /// @dev This is a one-way operation.
    function removeTier(mapping(uint256 => uint256) storage self, uint256 index) internal {
        setId({self: self, index: index});
    }

    /// @notice Set the bit at the given index.
    /// @param self The bitmap to set the bit in.
    /// @param index The index of the bit to set.
    function setId(mapping(uint256 => uint256) storage self, uint256 index) internal {
        self[_retrieveDepth(index)] |= _retrieveBitMask(index);
    }

    /// @notice Return the bit mask of a given index within its bitmap row.
    /// @param index The index to get a bit mask for.
    /// @return mask The bit mask for `index`.
    function _retrieveBitMask(uint256 index) internal pure returns (uint256 mask) {
        // The modulo keeps the bit offset inside one 256-bit bitmap word.
        // forge-lint: disable-next-line(incorrect-shift)
        return 1 << (index % 256);
    }

    /// @notice Return the line number (depth) of a given index within the bitmap matrix.
    function _retrieveDepth(uint256 index) internal pure returns (uint256) {
        return index >> 8; // div by 256
    }
}
