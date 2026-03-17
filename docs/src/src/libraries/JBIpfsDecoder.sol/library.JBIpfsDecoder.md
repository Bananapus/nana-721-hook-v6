# JBIpfsDecoder
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/libraries/JBIpfsDecoder.sol)

**Title:**
JBIpfsDecoder

Utilities to decode an IPFS hash.

This is fairly gas intensive due to multiple nested loops. Onchain IPFS hash decoding is not advised –
storing them as a string *might* be more efficient for that use-case.


## State Variables
### ALPHABET
Just a kind reminder to our readers.

Used in `base58ToString`


```solidity
bytes internal constant ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
```


## Functions
### decode

Decode an IPFS hash from a bytes32 and concatenate it with a base URI.


```solidity
function decode(string memory baseUri, bytes32 hexString) internal pure returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`baseUri`|`string`|The base URI to prepend to the decoded IPFS hash.|
|`hexString`|`bytes32`|The encoded IPFS hash to decode.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The full URI with the base URI and decoded IPFS hash.|


### _toBase58

Convert a hex string to base58

Written by Martin Ludfall - Licence: MIT


```solidity
function _toBase58(bytes memory source) private pure returns (string memory);
```

### _truncate


```solidity
function _truncate(uint8[] memory array, uint8 length) private pure returns (uint8[] memory);
```

### _reverse


```solidity
function _reverse(uint8[] memory input) private pure returns (uint8[] memory);
```

### _toAlphabet


```solidity
function _toAlphabet(uint8[] memory indices) private pure returns (bytes memory);
```

