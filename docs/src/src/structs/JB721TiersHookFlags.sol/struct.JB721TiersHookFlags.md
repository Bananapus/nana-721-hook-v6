# JB721TiersHookFlags
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/structs/JB721TiersHookFlags.sol)

**Notes:**
- member: noNewTiersWithReserves A boolean indicating whether attempts to add new tiers with a non-zero
`reserveFrequency` will revert.

- member: noNewTiersWithVotes A boolean indicating whether attempts to add new tiers with non-zero
`votingUnits` will revert.

- member: noNewTiersWithOwnerMinting A boolean indicating whether attempts to add new tiers with
`allowOwnerMint` set to true will revert.

- member: preventOverspending A boolean indicating whether payments attempting to spend more than the price of
the NFTs being minted will revert.

- member: issueTokensForSplits A boolean indicating whether payers receive token credit for the portion of
their payment that is routed to tier splits. When false (default), weight is reduced proportionally.


```solidity
struct JB721TiersHookFlags {
bool noNewTiersWithReserves;
bool noNewTiersWithVotes;
bool noNewTiersWithOwnerMinting;
bool preventOverspending;
bool issueTokensForSplits;
}
```

