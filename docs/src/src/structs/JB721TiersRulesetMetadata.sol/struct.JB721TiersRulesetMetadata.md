# JB721TiersRulesetMetadata
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/structs/JB721TiersRulesetMetadata.sol)

`JB721TiersHook` options which are packed and stored in the corresponding `JBRulesetMetadata.metadata` on a
per-ruleset basis.

**Notes:**
- member: pauseTransfers A boolean indicating whether NFT transfers are paused during this ruleset.

- member: pauseMintPendingReserves A boolean indicating whether pending/outstanding NFT reserves can be minted
during this ruleset.


```solidity
struct JB721TiersRulesetMetadata {
bool pauseTransfers;
bool pauseMintPendingReserves;
}
```

