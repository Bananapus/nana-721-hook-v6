# JB721InitTiersConfig
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/structs/JB721InitTiersConfig.sol)

Config to initialize a `JB721TiersHook` with tiers and price data.

The `tiers` must be sorted by category (from least to greatest).

**Notes:**
- member: tiers The tiers to initialize the hook with.

- member: currency The currency that the tier prices are denoted in. See `JBPrices`.

- member: decimals The number of decimals in the fixed point tier prices.


```solidity
struct JB721InitTiersConfig {
JB721TierConfig[] tiers;
uint32 currency;
uint8 decimals;
}
```

