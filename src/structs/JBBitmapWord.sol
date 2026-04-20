// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev A "word" is a 256-bit integer that stores the status of 256 bits (true/false values). Each row of the
/// `JBBitmap` matrix is a "word".
/// @custom:member The information stored at the index.
/// @custom:member The index.
struct JBBitmapWord {
    uint256 currentWord;
    uint256 currentDepth;
}
