// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {JB721TiersRulesetMetadataResolver} from "../../src/libraries/JB721TiersRulesetMetadataResolver.sol";
import {JB721TiersRulesetMetadata} from "../../src/structs/JB721TiersRulesetMetadata.sol";

/// @title TierEncodingProperties
/// @notice Formal verification of the pure bit-packing / token-id encoding semantics used by the 721 hook.
/// @dev Each property is DUAL-implemented: `check_*` for Halmos (symbolic) and `testFuzz_*` for forge.
///      All targets are SMT-tractable (constant shifts/masks, div/mul by literal constants) so Halmos can
///      decide them; the fuzz twin keeps the property green under `forge test`.
///
///      The ruleset-metadata properties call the REAL `JB721TiersRulesetMetadataResolver` library.
///      The packBools / token-id properties MIRROR the exact bit layout / arithmetic of
///      `JB721TiersHookStore._packBools`/`_unpackBools` and `_generateTokenId`/`tierIdOfToken`
///      (those symbols are `internal`/`private`); the mirror is the machine-checked spec of that layout.
contract TierEncodingProperties is Test {
    using JB721TiersRulesetMetadataResolver for uint16;

    // Token IDs encode tier as `tokenId / 1e9`; mints number from 1..1e9-1 within a tier.
    uint256 internal constant ONE_BILLION = 1_000_000_000;

    // ---------------------------------------------------------------------
    // Mirror of JB721TiersHookStore._packBools / _unpackBools bit layout.
    // bit0=allowOwnerMint, 1=transfersPausable, 2=useVotingUnits,
    // 3=cantBeRemoved, 4=cantIncreaseDiscountPercent, 5=cantBuyWithCredits.
    // ---------------------------------------------------------------------
    function _packBools(
        bool allowOwnerMint,
        bool transfersPausable,
        bool useVotingUnits,
        bool cantBeRemoved,
        bool cantIncreaseDiscountPercent,
        bool cantBuyWithCredits
    )
        internal
        pure
        returns (uint8 packed)
    {
        assembly {
            packed := or(allowOwnerMint, packed)
            packed := or(shl(0x1, transfersPausable), packed)
            packed := or(shl(0x2, useVotingUnits), packed)
            packed := or(shl(0x3, cantBeRemoved), packed)
            packed := or(shl(0x4, cantIncreaseDiscountPercent), packed)
            packed := or(shl(0x5, cantBuyWithCredits), packed)
        }
    }

    function _unpackBools(uint8 packed)
        internal
        pure
        returns (
            bool allowOwnerMint,
            bool transfersPausable,
            bool useVotingUnits,
            bool cantBeRemoved,
            bool cantIncreaseDiscountPercent,
            bool cantBuyWithCredits
        )
    {
        assembly {
            allowOwnerMint := iszero(iszero(and(0x1, packed)))
            transfersPausable := iszero(iszero(and(0x2, packed)))
            useVotingUnits := iszero(iszero(and(0x4, packed)))
            cantBeRemoved := iszero(iszero(and(0x8, packed)))
            cantIncreaseDiscountPercent := iszero(iszero(and(0x10, packed)))
            cantBuyWithCredits := iszero(iszero(and(0x20, packed)))
        }
    }

    // =====================================================================
    // P1: Ruleset metadata pack -> expand round-trips both boolean flags.
    // =====================================================================
    function check_rulesetMetadata_roundTrip(bool pauseTransfers, bool pauseMintPendingReserves) public pure {
        JB721TiersRulesetMetadata memory m = JB721TiersRulesetMetadata({
            pauseTransfers: pauseTransfers, pauseMintPendingReserves: pauseMintPendingReserves
        });

        uint256 packed = JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(m);
        JB721TiersRulesetMetadata memory back = JB721TiersRulesetMetadataResolver.expandMetadata(uint16(packed));

        assert(back.pauseTransfers == pauseTransfers);
        assert(back.pauseMintPendingReserves == pauseMintPendingReserves);
    }

    function testFuzz_rulesetMetadata_roundTrip(bool pauseTransfers, bool pauseMintPendingReserves) public {
        JB721TiersRulesetMetadata memory m = JB721TiersRulesetMetadata({
            pauseTransfers: pauseTransfers, pauseMintPendingReserves: pauseMintPendingReserves
        });

        uint256 packed = JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(m);
        JB721TiersRulesetMetadata memory back = JB721TiersRulesetMetadataResolver.expandMetadata(uint16(packed));

        assertEq(back.pauseTransfers, pauseTransfers);
        assertEq(back.pauseMintPendingReserves, pauseMintPendingReserves);
    }

    // =====================================================================
    // P2: Ruleset metadata fields are isolated to their own bit & only set bits 0/1.
    // =====================================================================
    function check_rulesetMetadata_fieldIsolation(bool a, bool b) public pure {
        uint256 packed = JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(
            JB721TiersRulesetMetadata({pauseTransfers: a, pauseMintPendingReserves: b})
        );

        // Only bits 0 and 1 may ever be set.
        assert(packed < 4);
        // bit0 reflects pauseTransfers, bit1 reflects pauseMintPendingReserves.
        assert(JB721TiersRulesetMetadataResolver.transfersPaused(packed) == a);
        assert(JB721TiersRulesetMetadataResolver.mintPendingReservesPaused(packed) == b);
    }

    function testFuzz_rulesetMetadata_fieldIsolation(uint256 data) public {
        // transfersPaused reads bit0, mintPendingReservesPaused reads bit1 — independent of other bits.
        bool t = JB721TiersRulesetMetadataResolver.transfersPaused(data);
        bool m = JB721TiersRulesetMetadataResolver.mintPendingReservesPaused(data);
        assertEq(t, (data & 1) == 1);
        assertEq(m, ((data >> 1) & 1) == 1);
    }

    // =====================================================================
    // P3: packBools -> unpackBools is the identity for all 6 flags.
    // =====================================================================
    function check_packBools_roundTrip(bool a, bool b, bool c, bool d, bool e, bool f) public pure {
        uint8 packed = _packBools(a, b, c, d, e, f);
        (bool a2, bool b2, bool c2, bool d2, bool e2, bool f2) = _unpackBools(packed);
        assert(a2 == a);
        assert(b2 == b);
        assert(c2 == c);
        assert(d2 == d);
        assert(e2 == e);
        assert(f2 == f);
        // Only the low 6 bits are ever used.
        assert(packed < 64);
    }

    function testFuzz_packBools_roundTrip(bool a, bool b, bool c, bool d, bool e, bool f) public {
        uint8 packed = _packBools(a, b, c, d, e, f);
        (bool a2, bool b2, bool c2, bool d2, bool e2, bool f2) = _unpackBools(packed);
        assertEq(a2, a);
        assertEq(b2, b);
        assertEq(c2, c);
        assertEq(d2, d);
        assertEq(e2, e);
        assertEq(f2, f);
        assertLt(packed, 64);
    }

    // =====================================================================
    // P4: unpackBools ignores bits >= 6 (the unused high bits of the uint8).
    // =====================================================================
    function check_packBools_unpackIgnoresHighBits(uint8 packed) public pure {
        (bool a, bool b, bool c, bool d, bool e, bool f) = _unpackBools(packed);
        // Re-packing the decoded low bits must reproduce only the meaningful low-6-bit pattern.
        uint8 repacked = _packBools(a, b, c, d, e, f);
        assert(repacked == (packed & 0x3f));
    }

    function testFuzz_packBools_unpackIgnoresHighBits(uint8 packed) public {
        (bool a, bool b, bool c, bool d, bool e, bool f) = _unpackBools(packed);
        uint8 repacked = _packBools(a, b, c, d, e, f);
        assertEq(repacked, packed & 0x3f);
    }

    // =====================================================================
    // P5: token-id encode/decode round-trips the tier ID.
    //     _generateTokenId(tier, n) = tier*1e9 + n ; tierIdOfToken(id) = id/1e9.
    //     For any tokenNumber in [0, 1e9), the tier is recoverable.
    // =====================================================================
    function check_tokenId_tierRoundTrip(uint16 tierId, uint32 tokenNumber) public pure {
        // tokenNumber within a tier is bounded by initialSupply (uint32) and, in practice, < 1e9.
        vm.assume(tokenNumber < ONE_BILLION);
        uint256 tokenId = (uint256(tierId) * ONE_BILLION) + uint256(tokenNumber);
        // Mirror of store.tierIdOfToken.
        assert(tokenId / ONE_BILLION == uint256(tierId));
    }

    function testFuzz_tokenId_tierRoundTrip(uint16 tierId, uint256 tokenNumber) public {
        tokenNumber = bound(tokenNumber, 0, ONE_BILLION - 1);
        uint256 tokenId = (uint256(tierId) * ONE_BILLION) + tokenNumber;
        assertEq(tokenId / ONE_BILLION, uint256(tierId));
    }

    // =====================================================================
    // P6: distinct tiers never share a token ID (no cross-tier collision).
    //     Different tier IDs produce disjoint [tier*1e9, tier*1e9+1e9) ranges.
    // =====================================================================
    function check_tokenId_noCrossTierCollision(uint16 tierA, uint16 tierB, uint32 nA, uint32 nB) public pure {
        vm.assume(tierA != tierB);
        vm.assume(nA < ONE_BILLION && nB < ONE_BILLION);
        uint256 idA = (uint256(tierA) * ONE_BILLION) + uint256(nA);
        uint256 idB = (uint256(tierB) * ONE_BILLION) + uint256(nB);
        assert(idA != idB);
    }

    function testFuzz_tokenId_noCrossTierCollision(uint16 tierA, uint16 tierB, uint256 nA, uint256 nB) public {
        vm.assume(tierA != tierB);
        nA = bound(nA, 0, ONE_BILLION - 1);
        nB = bound(nB, 0, ONE_BILLION - 1);
        uint256 idA = (uint256(tierA) * ONE_BILLION) + nA;
        uint256 idB = (uint256(tierB) * ONE_BILLION) + nB;
        assertTrue(idA != idB);
    }
}
