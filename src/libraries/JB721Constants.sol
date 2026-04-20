// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Global constants used across 721 hook contracts.
library JB721Constants {
    uint16 public constant DISCOUNT_DENOMINATOR = 200;

    /// @notice The metadata ID used to identify the 721 beneficiary entry in payment metadata.
    /// @dev When a sucker pays on behalf of a remote user, the real user's address is embedded under this key
    /// so NFTs mint to the correct recipient.
    bytes4 public constant BENEFICIARY_METADATA_ID = bytes4(keccak256("JB_721_BENEFICIARY"));
}
