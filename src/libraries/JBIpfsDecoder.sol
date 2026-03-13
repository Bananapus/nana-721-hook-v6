// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title JBIpfsDecoder
/// @notice Utilities to decode an IPFS hash.
/// @dev This is fairly gas intensive due to multiple nested loops. Onchain IPFS hash decoding is not advised –
/// storing them as a string *might* be more efficient for that use-case.
library JBIpfsDecoder {
    //*********************************************************************//
    // ------------------- internal constant properties ------------------ //
    //*********************************************************************//

    /// @notice Just a kind reminder to our readers.
    /// @dev Used in `base58ToString`
    bytes internal constant ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

    /// @notice Decode an IPFS hash from a bytes32 and concatenate it with a base URI.
    /// @param baseUri The base URI to prepend to the decoded IPFS hash.
    /// @param hexString The encoded IPFS hash to decode.
    /// @return The full URI with the base URI and decoded IPFS hash.
    function decode(string memory baseUri, bytes32 hexString) internal pure returns (string memory) {
        // All IPFS hashes start with a fixed sequence (0x12 and 0x20)
        bytes memory completeHexString = abi.encodePacked(bytes2(0x1220), hexString);

        // Convert the hex string to a hash
        string memory ipfsHash = _toBase58(completeHexString);

        // Concatenate with the base URI
        return string(abi.encodePacked(baseUri, ipfsHash));
    }

    /// @notice Convert a hex string to base58
    /// @notice Written by Martin Ludfall - Licence: MIT
    function _toBase58(bytes memory source) private pure returns (string memory) {
        if (source.length == 0) return new string(0);

        uint8[] memory digits = new uint8[](46); // hash size with the prefix

        digits[0] = 0;

        uint8 digitlength = 1;
        uint256 sourceLength = source.length;

        for (uint256 i; i < sourceLength; i++) {
            uint256 carry = uint8(source[i]);

            for (uint256 j; j < digitlength;) {
                carry += uint256(digits[j]) << 8; // mul 256
                digits[j] = uint8(carry % 58);
                carry = carry / 58;

                unchecked {
                    ++j;
                }
            }

            while (carry > 0) {
                digits[digitlength] = uint8(carry % 58);
                unchecked {
                    ++digitlength;
                }
                carry = carry / 58;
            }
        }
        return string(_toAlphabet(_reverse(_truncate({array: digits, length: digitlength}))));
    }

    function _truncate(uint8[] memory array, uint8 length) private pure returns (uint8[] memory) {
        uint8[] memory output = new uint8[](length);
        for (uint256 i; i < length; i++) {
            output[i] = array[i];
        }
        return output;
    }

    function _reverse(uint8[] memory input) private pure returns (uint8[] memory) {
        uint256 inputLength = input.length;
        uint8[] memory output = new uint8[](inputLength);
        for (uint256 i; i < inputLength; i++) {
            unchecked {
                output[i] = input[input.length - 1 - i];
            }
        }
        return output;
    }

    function _toAlphabet(uint8[] memory indices) private pure returns (bytes memory) {
        uint256 indicesLength = indices.length;
        bytes memory output = new bytes(indicesLength);
        for (uint256 i; i < indicesLength; i++) {
            output[i] = ALPHABET[indices[i]];
        }
        return output;
    }
}
