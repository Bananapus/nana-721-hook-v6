// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import {JB721TiersRulesetMetadataResolver} from "../../src/libraries/JB721TiersRulesetMetadataResolver.sol";
import {JB721TiersRulesetMetadata} from "../../src/structs/JB721TiersRulesetMetadata.sol";

/// @notice Unit + fuzz tests for `JB721TiersRulesetMetadataResolver`.
contract TestJB721TiersRulesetMetadataResolver is Test {
    //*********************************************************************//
    // --- pack: individual flags ---------------------------------------- //
    //*********************************************************************//

    function test_pack_allFalse() public {
        JB721TiersRulesetMetadata memory meta =
            JB721TiersRulesetMetadata({pauseTransfers: false, pauseMintPendingReserves: false});
        uint256 packed = JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(meta);
        assertEq(packed, 0, "both false should pack to 0");
    }

    function test_pack_pauseTransfersOnly() public {
        JB721TiersRulesetMetadata memory meta =
            JB721TiersRulesetMetadata({pauseTransfers: true, pauseMintPendingReserves: false});
        uint256 packed = JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(meta);
        assertEq(packed, 1, "pauseTransfers only should pack to 1");
    }

    function test_pack_pauseMintPendingReservesOnly() public {
        JB721TiersRulesetMetadata memory meta =
            JB721TiersRulesetMetadata({pauseTransfers: false, pauseMintPendingReserves: true});
        uint256 packed = JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(meta);
        assertEq(packed, 2, "pauseMintPendingReserves only should pack to 2");
    }

    function test_pack_bothTrue() public {
        JB721TiersRulesetMetadata memory meta =
            JB721TiersRulesetMetadata({pauseTransfers: true, pauseMintPendingReserves: true});
        uint256 packed = JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(meta);
        assertEq(packed, 3, "both true should pack to 3");
    }

    //*********************************************************************//
    // --- transfersPaused / mintPendingReservesPaused -------------------- //
    //*********************************************************************//

    function test_transfersPaused() public {
        assertFalse(JB721TiersRulesetMetadataResolver.transfersPaused(0));
        assertTrue(JB721TiersRulesetMetadataResolver.transfersPaused(1));
        assertFalse(JB721TiersRulesetMetadataResolver.transfersPaused(2));
        assertTrue(JB721TiersRulesetMetadataResolver.transfersPaused(3));
    }

    function test_mintPendingReservesPaused() public {
        assertFalse(JB721TiersRulesetMetadataResolver.mintPendingReservesPaused(0));
        assertFalse(JB721TiersRulesetMetadataResolver.mintPendingReservesPaused(1));
        assertTrue(JB721TiersRulesetMetadataResolver.mintPendingReservesPaused(2));
        assertTrue(JB721TiersRulesetMetadataResolver.mintPendingReservesPaused(3));
    }

    //*********************************************************************//
    // --- expandMetadata ------------------------------------------------ //
    //*********************************************************************//

    function test_expandMetadata_zero() public {
        JB721TiersRulesetMetadata memory meta = JB721TiersRulesetMetadataResolver.expandMetadata(0);
        assertFalse(meta.pauseTransfers);
        assertFalse(meta.pauseMintPendingReserves);
    }

    function test_expandMetadata_one() public {
        JB721TiersRulesetMetadata memory meta = JB721TiersRulesetMetadataResolver.expandMetadata(1);
        assertTrue(meta.pauseTransfers);
        assertFalse(meta.pauseMintPendingReserves);
    }

    function test_expandMetadata_two() public {
        JB721TiersRulesetMetadata memory meta = JB721TiersRulesetMetadataResolver.expandMetadata(2);
        assertFalse(meta.pauseTransfers);
        assertTrue(meta.pauseMintPendingReserves);
    }

    function test_expandMetadata_three() public {
        JB721TiersRulesetMetadata memory meta = JB721TiersRulesetMetadataResolver.expandMetadata(3);
        assertTrue(meta.pauseTransfers);
        assertTrue(meta.pauseMintPendingReserves);
    }

    //*********************************************************************//
    // --- Round-Trip ----------------------------------------------------- //
    //*********************************************************************//

    function test_packExpandRoundTrip_allCombinations() public {
        for (uint256 i; i < 4; i++) {
            bool transfers = (i & 1) == 1;
            bool reserves = (i & 2) == 2;

            JB721TiersRulesetMetadata memory meta =
                JB721TiersRulesetMetadata({pauseTransfers: transfers, pauseMintPendingReserves: reserves});

            uint256 packed = JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(meta);
            JB721TiersRulesetMetadata memory expanded =
                JB721TiersRulesetMetadataResolver.expandMetadata(uint16(packed));

            assertEq(expanded.pauseTransfers, transfers, "transfers round-trip");
            assertEq(expanded.pauseMintPendingReserves, reserves, "reserves round-trip");
        }
    }

    //*********************************************************************//
    // --- Fuzz ---------------------------------------------------------- //
    //*********************************************************************//

    function testFuzz_packExpandRoundTrip(bool pauseTransfers, bool pauseMintPendingReserves) public {
        JB721TiersRulesetMetadata memory meta = JB721TiersRulesetMetadata({
            pauseTransfers: pauseTransfers,
            pauseMintPendingReserves: pauseMintPendingReserves
        });

        uint256 packed = JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(meta);
        JB721TiersRulesetMetadata memory expanded = JB721TiersRulesetMetadataResolver.expandMetadata(uint16(packed));

        assertEq(expanded.pauseTransfers, pauseTransfers, "fuzz transfers round-trip");
        assertEq(expanded.pauseMintPendingReserves, pauseMintPendingReserves, "fuzz reserves round-trip");
    }

    function testFuzz_transfersPaused_bitIsolation(uint256 data) public {
        bool result = JB721TiersRulesetMetadataResolver.transfersPaused(data);
        assertEq(result, (data & 1) == 1, "transfersPaused should check bit 0");
    }

    function testFuzz_mintPendingReservesPaused_bitIsolation(uint256 data) public {
        bool result = JB721TiersRulesetMetadataResolver.mintPendingReservesPaused(data);
        assertEq(result, ((data >> 1) & 1) == 1, "mintPendingReservesPaused should check bit 1");
    }

    function testFuzz_pack_onlyUsesLow2Bits(bool a, bool b) public {
        JB721TiersRulesetMetadata memory meta =
            JB721TiersRulesetMetadata({pauseTransfers: a, pauseMintPendingReserves: b});
        uint256 packed = JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(meta);
        assertEq(packed & ~uint256(3), 0, "packed value should only use bits 0 and 1");
    }
}
