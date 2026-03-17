# IJB721TokenUriResolver
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/interfaces/IJB721TokenUriResolver.sol)

Resolves token URIs for 721 NFTs.


## Functions
### tokenUriOf

Resolve the token URI for the given NFT.


```solidity
function tokenUriOf(address nft, uint256 tokenId) external view returns (string memory tokenUri);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nft`|`address`|The address of the NFT contract.|
|`tokenId`|`uint256`|The token ID of the NFT to get the URI of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenUri`|`string`|The token URI.|


