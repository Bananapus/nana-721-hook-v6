# JBBitmapWord
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/structs/JBBitmapWord.sol)

A "word" is a 256-bit integer that stores the status of 256 bits (true/false values). Each row of the
`JBBitmap` matrix is a "word".

**Notes:**
- member: The information stored at the index.

- member: The index.


```solidity
struct JBBitmapWord {
uint256 currentWord;
uint256 currentDepth;
}
```

