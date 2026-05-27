// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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
    bytes internal constant _ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

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

    /// @notice Return a new array containing the elements of `input` in reverse order.
    /// @dev Used by `_toBase58` after the base-58 digit accumulator is finalised — the conversion algorithm
    /// emits least-significant digits first, but base-58 strings are read most-significant first.
    /// @param input The array to reverse.
    /// @return output A new array of the same length with elements in reverse order.
    function _reverse(uint8[] memory input) private pure returns (uint8[] memory) {
        uint256 inputLength = input.length;
        uint8[] memory output = new uint8[](inputLength);
        for (uint256 i; i < inputLength;) {
            unchecked {
                // Read from the tail of `input` and write to the head of `output`.
                output[i] = input[input.length - 1 - i];
                ++i;
            }
        }
        return output;
    }

    /// @notice Map each base-58 digit (0–57) to its corresponding character in `_ALPHABET`.
    /// @dev Final stage of `_toBase58`: turns the numeric digit array into the canonical base-58 string bytes.
    /// @param indices Each element must satisfy `0 <= indices[i] < 58`; out-of-range values revert via index OOB.
    /// @return output ASCII bytes with `output[i] = _ALPHABET[indices[i]]`.
    function _toAlphabet(uint8[] memory indices) private pure returns (bytes memory) {
        uint256 indicesLength = indices.length;
        bytes memory output = new bytes(indicesLength);
        for (uint256 i; i < indicesLength;) {
            output[i] = _ALPHABET[indices[i]];

            unchecked {
                ++i;
            }
        }
        return output;
    }

    /// @notice Convert a hex byte string to its base-58 string representation.
    /// @notice Written by Martin Ludfall — Licence: MIT.
    /// @dev Classic "long division by 58" base conversion: iterate the source bytes high-to-low, carrying remainders
    /// through the digit accumulator. After the loop, `digits[0..digitlength)` holds the base-58 representation in
    /// little-endian order; the final composition reverses and maps to ASCII via `_toAlphabet(_reverse(...))`.
    /// @param source The source bytes to convert (multibase-prefixed IPFS hash, in this library's usage).
    /// @return The base-58 encoded string.
    function _toBase58(bytes memory source) private pure returns (string memory) {
        if (source.length == 0) return new string(0);

        uint8[] memory digits = new uint8[](46); // hash size with the prefix

        digits[0] = 0;

        uint8 digitlength = 1;
        uint256 sourceLength = source.length;

        for (uint256 i; i < sourceLength;) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 carry = uint8(source[i]);

            for (uint256 j; j < digitlength;) {
                carry += uint256(digits[j]) << 8; // mul 256
                // forge-lint: disable-next-line(unsafe-typecast)
                digits[j] = uint8(carry % 58);
                carry = carry / 58;

                unchecked {
                    ++j;
                }
            }

            while (carry > 0) {
                // forge-lint: disable-next-line(unsafe-typecast)
                digits[digitlength] = uint8(carry % 58);
                unchecked {
                    ++digitlength;
                }
                carry = carry / 58;
            }

            unchecked {
                ++i;
            }
        }
        return string(_toAlphabet(_reverse(_truncate({array: digits, length: digitlength}))));
    }

    /// @notice Copy the first `length` elements of `array` into a new, exactly-sized array.
    /// @dev `_toBase58` allocates a fixed 46-byte scratch buffer but only fills `digitlength` of it; this trims the
    /// trailing zeros so downstream stages (`_reverse`, `_toAlphabet`) see only the meaningful digits.
    /// @param array The source array. Must have `array.length >= length`.
    /// @param length Number of leading elements to copy.
    /// @return output A new array of exactly `length` elements containing the prefix of `array`.
    function _truncate(uint8[] memory array, uint8 length) private pure returns (uint8[] memory) {
        uint8[] memory output = new uint8[](length);
        for (uint256 i; i < length;) {
            output[i] = array[i];

            unchecked {
                ++i;
            }
        }
        return output;
    }
}
