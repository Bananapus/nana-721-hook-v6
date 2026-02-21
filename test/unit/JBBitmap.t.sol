// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import {JBBitmap} from "../../src/libraries/JBBitmap.sol";
import {JBBitmapWord} from "../../src/structs/JBBitmapWord.sol";

/// @notice Unit + fuzz tests for `JBBitmap`.
contract TestJBBitmap is Test {
    using JBBitmap for mapping(uint256 => uint256);
    using JBBitmap for JBBitmapWord;

    mapping(uint256 => uint256) internal bitmap;

    //*********************************************************************//
    // --- readId -------------------------------------------------------- //
    //*********************************************************************//

    function test_readId_initiallyZero() public {
        JBBitmapWord memory word = bitmap.readId(0);
        assertEq(word.currentWord, 0, "initial word should be 0");
        assertEq(word.currentDepth, 0, "depth for index 0 should be 0");
    }

    function test_readId_depthCalculation() public {
        // Index 255 is in depth 0, index 256 is in depth 1.
        JBBitmapWord memory word0 = bitmap.readId(255);
        assertEq(word0.currentDepth, 0, "index 255 should be depth 0");

        JBBitmapWord memory word1 = bitmap.readId(256);
        assertEq(word1.currentDepth, 1, "index 256 should be depth 1");

        JBBitmapWord memory word2 = bitmap.readId(512);
        assertEq(word2.currentDepth, 2, "index 512 should be depth 2");
    }

    //*********************************************************************//
    // --- removeTier / isTierIdRemoved ---------------------------------- //
    //*********************************************************************//

    function test_removeTier_setsbit() public {
        assertFalse(bitmap.isTierIdRemoved(5), "should not be removed initially");

        bitmap.removeTier(5);

        assertTrue(bitmap.isTierIdRemoved(5), "should be removed after removeTier");
    }

    function test_removeTier_doesNotAffectOtherBits() public {
        bitmap.removeTier(5);

        assertFalse(bitmap.isTierIdRemoved(4), "adjacent bit should not be affected");
        assertFalse(bitmap.isTierIdRemoved(6), "adjacent bit should not be affected");
        assertFalse(bitmap.isTierIdRemoved(0), "index 0 should not be affected");
    }

    function test_removeTier_multipleBitsInSameWord() public {
        bitmap.removeTier(0);
        bitmap.removeTier(1);
        bitmap.removeTier(255);

        assertTrue(bitmap.isTierIdRemoved(0));
        assertTrue(bitmap.isTierIdRemoved(1));
        assertTrue(bitmap.isTierIdRemoved(255));
        assertFalse(bitmap.isTierIdRemoved(2));
    }

    function test_removeTier_acrossWords() public {
        bitmap.removeTier(0);    // depth 0
        bitmap.removeTier(256);  // depth 1
        bitmap.removeTier(512);  // depth 2

        assertTrue(bitmap.isTierIdRemoved(0));
        assertTrue(bitmap.isTierIdRemoved(256));
        assertTrue(bitmap.isTierIdRemoved(512));

        assertFalse(bitmap.isTierIdRemoved(1));
        assertFalse(bitmap.isTierIdRemoved(257));
        assertFalse(bitmap.isTierIdRemoved(513));
    }

    function test_removeTier_idempotent() public {
        bitmap.removeTier(10);
        bitmap.removeTier(10); // Remove again.
        assertTrue(bitmap.isTierIdRemoved(10), "should still be removed");
    }

    //*********************************************************************//
    // --- isTierIdRemoved (memory struct variant) ----------------------- //
    //*********************************************************************//

    function test_isTierIdRemoved_memoryStruct() public {
        bitmap.removeTier(3);

        JBBitmapWord memory word = bitmap.readId(3);
        assertTrue(word.isTierIdRemoved(3), "memory struct should read removed bit");
        assertFalse(word.isTierIdRemoved(4), "memory struct should read non-removed bit");
    }

    function test_isTierIdRemoved_wrongDepthReturnsWrong() public {
        bitmap.removeTier(3); // depth 0

        // Read a word from depth 1 — should not see index 3's removal.
        JBBitmapWord memory word = bitmap.readId(256);
        assertFalse(word.isTierIdRemoved(3), "wrong depth should not see bit");
    }

    //*********************************************************************//
    // --- refreshBitmapNeeded ------------------------------------------- //
    //*********************************************************************//

    function test_refreshBitmapNeeded_sameDepth() public {
        JBBitmapWord memory word = bitmap.readId(0);
        assertFalse(word.refreshBitmapNeeded(100), "same depth should not need refresh");
        assertFalse(word.refreshBitmapNeeded(255), "still depth 0, no refresh needed");
    }

    function test_refreshBitmapNeeded_differentDepth() public {
        JBBitmapWord memory word = bitmap.readId(0);
        assertTrue(word.refreshBitmapNeeded(256), "depth 1 should need refresh from depth 0");
        assertTrue(word.refreshBitmapNeeded(512), "depth 2 should need refresh from depth 0");
    }

    //*********************************************************************//
    // --- Fuzz Tests ---------------------------------------------------- //
    //*********************************************************************//

    function testFuzz_removeTier_roundTrip(uint16 index) public {
        assertFalse(bitmap.isTierIdRemoved(index), "should start unremoved");

        bitmap.removeTier(index);

        assertTrue(bitmap.isTierIdRemoved(index), "should be removed after removeTier");
    }

    function testFuzz_removeTier_isolatedBit(uint16 indexA, uint16 indexB) public {
        vm.assume(indexA != indexB);

        bitmap.removeTier(indexA);

        assertTrue(bitmap.isTierIdRemoved(indexA), "A should be removed");
        assertFalse(bitmap.isTierIdRemoved(indexB), "B should not be removed");
    }

    function testFuzz_readId_depthMatchesIndex(uint16 index) public {
        JBBitmapWord memory word = bitmap.readId(index);
        assertEq(word.currentDepth, uint256(index) >> 8, "depth should be index / 256");
    }

    function testFuzz_refreshBitmapNeeded_consistency(uint16 indexA, uint16 indexB) public {
        JBBitmapWord memory word = bitmap.readId(indexA);
        bool needed = word.refreshBitmapNeeded(indexB);
        // Refresh is needed iff depths differ.
        assertEq(needed, (uint256(indexA) >> 8) != (uint256(indexB) >> 8), "refresh iff different depth");
    }

    function testFuzz_removeTier_multipleBits(uint8 a, uint8 b, uint8 c) public {
        vm.assume(a != b && b != c && a != c);

        bitmap.removeTier(a);
        bitmap.removeTier(b);
        bitmap.removeTier(c);

        assertTrue(bitmap.isTierIdRemoved(a));
        assertTrue(bitmap.isTierIdRemoved(b));
        assertTrue(bitmap.isTierIdRemoved(c));
    }
}
