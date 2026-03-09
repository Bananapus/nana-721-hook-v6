// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Resolves token URIs for 721 NFTs.
interface IJB721TokenUriResolver {
    /// @notice Resolve the token URI for the given NFT.
    /// @param nft The address of the NFT contract.
    /// @param tokenId The token ID of the NFT to get the URI of.
    /// @return tokenUri The token URI.
    function tokenUriOf(address nft, uint256 tokenId) external view returns (string memory tokenUri);
}
