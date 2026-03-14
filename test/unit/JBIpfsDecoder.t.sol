// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "forge-std/Test.sol";

import {JBIpfsDecoder} from "../../src/libraries/JBIpfsDecoder.sol";

/// @notice Unit tests for `JBIpfsDecoder`.
contract TestJBIpfsDecoder is Test {
    /// @notice Known IPFS CID v0 hash for testing.
    /// @dev Obtained by hashing a known payload: the CID for the hex 0x1220... prefix + this hash should decode to a
    /// valid base58 string starting with "Qm".
    bytes32 constant TEST_HASH = 0x7465737468617368000000000000000000000000000000000000000000000000;

    //*********************************************************************//
    // --- decode: basic output ------------------------------------------ //
    //*********************************************************************//

    function test_decode_prependsBaseUri() public {
        string memory result = JBIpfsDecoder.decode("ipfs://", TEST_HASH);
        // Result must start with the base URI.
        bytes memory resultBytes = bytes(result);
        bytes memory prefix = bytes("ipfs://");
        for (uint256 i; i < prefix.length; i++) {
            assertEq(resultBytes[i], prefix[i], "prefix mismatch");
        }
    }

    function test_decode_emptyBaseUri() public {
        string memory result = JBIpfsDecoder.decode("", TEST_HASH);
        // Should still produce a non-empty base58 hash.
        assertTrue(bytes(result).length > 0, "should produce output with empty base URI");
    }

    function test_decode_outputStartsWithQm() public {
        // All CIDv0 hashes start with "Qm" because the 0x1220 prefix encodes to "Qm" in base58.
        string memory result = JBIpfsDecoder.decode("", TEST_HASH);
        bytes memory resultBytes = bytes(result);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(resultBytes[0], bytes1("Q"), "first char should be Q");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(resultBytes[1], bytes1("m"), "second char should be m");
    }

    function test_decode_outputLength() public {
        // CIDv0 hashes are always 46 characters in base58.
        string memory result = JBIpfsDecoder.decode("", TEST_HASH);
        assertEq(bytes(result).length, 46, "CIDv0 base58 hash should be 46 characters");
    }

    //*********************************************************************//
    // --- decode: determinism ------------------------------------------- //
    //*********************************************************************//

    function test_decode_deterministic() public {
        string memory a = JBIpfsDecoder.decode("ipfs://", TEST_HASH);
        string memory b = JBIpfsDecoder.decode("ipfs://", TEST_HASH);
        assertEq(keccak256(bytes(a)), keccak256(bytes(b)), "same input should produce same output");
    }

    function test_decode_differentHashesDifferentOutput() public {
        bytes32 hashA = bytes32(uint256(1));
        bytes32 hashB = bytes32(uint256(2));
        string memory a = JBIpfsDecoder.decode("", hashA);
        string memory b = JBIpfsDecoder.decode("", hashB);
        assertTrue(keccak256(bytes(a)) != keccak256(bytes(b)), "different hashes should produce different output");
    }

    //*********************************************************************//
    // --- decode: base58 alphabet --------------------------------------- //
    //*********************************************************************//

    function test_decode_onlyBase58Chars() public {
        string memory result = JBIpfsDecoder.decode("", TEST_HASH);
        bytes memory resultBytes = bytes(result);
        bytes memory alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

        for (uint256 i; i < resultBytes.length; i++) {
            bool found;
            for (uint256 j; j < alphabet.length; j++) {
                if (resultBytes[i] == alphabet[j]) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, "output should only contain base58 characters");
        }
    }

    //*********************************************************************//
    // --- decode: fuzz -------------------------------------------------- //
    //*********************************************************************//

    function testFuzz_decode_alwaysProduces46Chars(bytes32 hash) public {
        string memory result = JBIpfsDecoder.decode("", hash);
        assertEq(bytes(result).length, 46, "any hash should produce 46-char CIDv0");
    }

    function testFuzz_decode_alwaysStartsWithQm(bytes32 hash) public {
        string memory result = JBIpfsDecoder.decode("", hash);
        bytes memory resultBytes = bytes(result);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(resultBytes[0], bytes1("Q"), "first char should be Q");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(resultBytes[1], bytes1("m"), "second char should be m");
    }

    function testFuzz_decode_prependsBaseUri(bytes32 hash, uint8 baseLen) public {
        // Create a base URI of varying length (0-255 chars).
        bytes memory base = new bytes(baseLen);
        for (uint256 i; i < baseLen; i++) {
            base[i] = "x";
        }
        string memory baseUri = string(base);
        string memory result = JBIpfsDecoder.decode(baseUri, hash);
        assertEq(bytes(result).length, uint256(baseLen) + 46, "output length = base + 46");
    }

    function testFuzz_decode_onlyBase58Chars(bytes32 hash) public {
        string memory result = JBIpfsDecoder.decode("", hash);
        bytes memory resultBytes = bytes(result);
        bytes memory alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

        for (uint256 i; i < resultBytes.length; i++) {
            bool found;
            for (uint256 j; j < alphabet.length; j++) {
                if (resultBytes[i] == alphabet[j]) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, "all chars should be in base58 alphabet");
        }
    }
}
