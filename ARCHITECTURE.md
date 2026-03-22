# nana-721-hook-v6 — Architecture

## Purpose

NFT tier system for Juicebox V6. Allows projects to attach tiered NFT minting to payments and use NFTs as cash-out hooks. Supports on-chain and off-chain metadata, category-based sorting, and configurable pricing with discounts.

The design permits a high theoretical tier ceiling, but several important reads and cash-out calculations still scale
with `maxTierId`. In practice, this should be treated as a curated-catalog hook with an explicit operating envelope,
not as a guarantee that very large catalogs are comfortable to run on-chain.

## Contract Map

```
src/
├── JB721TiersHook.sol                — Pay + cash-out hook that mints/burns tiered NFTs
├── JB721TiersHookStore.sol           — Tier configuration storage and pricing logic
├── JB721TiersHookDeployer.sol        — Deploys hook+store pairs (clone-based)
├── JB721TiersHookProjectDeployer.sol — Launches project + hook in one transaction
├── abstract/
│   ├── JB721Hook.sol                 — Base ERC-721 + pay/cashout hook integration
│   └── ERC721.sol                    — Minimal ERC-721 implementation
├── libraries/
│   ├── JB721Constants.sol            — Global constants (DISCOUNT_DENOMINATOR)
│   ├── JB721TiersHookLib.sol         — Split calculations, price normalization, weight math, fund distribution
│   ├── JB721TiersRulesetMetadataResolver.sol — Bit-packed 721 ruleset metadata (transfer/reserve pause flags)
│   ├── JBBitmap.sol                  — Bitmap utilities for tier removal tracking
│   └── JBIpfsDecoder.sol             — IPFS CID encoding/decoding for token URIs
├── interfaces/                       — All interfaces (IJB721TiersHook, etc.)
└── structs/                          — Tier config, mint context, cash-out structs
```

## Key Data Flows

### NFT Minting (via Payment)
```
User → JBMultiTerminal.pay(metadata)
  → beforePayRecordedWith()
    → calculateSplitAmounts(): per-tier split amounts (in tier pricing denomination)
    → convertSplitAmounts(): convert to payment token denomination (if currencies differ)
    → calculateWeight(): adjust weight down by split fraction
  → JBTerminalStore records payment
  → afterPayRecordedWith() → _processPayment()
    → Normalize payment value to tier pricing currency
    → Decode tier IDs from metadata
    → For each tier:
      → Validate: not removed, not paused, supply available
      → Check price (with optional discount, normalized to tier pricing currency)
      → Mint NFT to beneficiary
    → Leftover amount stored as pay credits (revert if overspending not allowed)
    → Distribute split funds (priority: split.hook > split.projectId > split.beneficiary)
```

### NFT Cash Out
```
Holder → JBMultiTerminal.cashOutTokensOf()
  → JB721TiersHook.afterCashOutRecordedWith()
    → Burn specified NFT token IDs
    → Each NFT's cash-out weight = tier.price (full price, ignoring discounts)
    → Total cash-out weight (denominator) = sum of (tier.price * minted+pending) across all tiers
```

### Tier Management
```
Owner → JB721TiersHook.adjustTiers()
  → Add new tiers (must be sorted by category)
  → Remove existing tiers (flags, doesn't delete)
```

## Design Decisions

1. **Clone deployment**: `JB721TiersHookDeployer` uses `LibClone.clone()` (or `cloneDeterministic` with a salt) to deploy lightweight proxies of a reference `JB721TiersHook`, then calls `initialize()`. This keeps deployment gas low and ensures all hooks share identical bytecode.

2. **Library extraction (EIP-170)**: `JB721TiersHookLib` is an external library called via DELEGATECALL. Split calculations, price normalization, fund distribution, and IPFS decoding are extracted there to keep the hook contract under the 24,576 byte EIP-170 size limit.

3. **Category sorting**: Tiers added via `recordAddTiers` must be sorted by `category` (ascending). The store enforces this with `InvalidCategorySortOrder` and maintains a linked-list structure indexed by category for efficient iteration.

4. **Cash-out weight uses full price**: `cashOutWeightOf` returns `tier.price` per NFT -- the original undiscounted price. Discounts are transient purchase incentives; an NFT's share of the cash-out pool is always based on its tier's original price. This prevents discount changes from retroactively altering the cash-out value of already-minted NFTs.

5. **Discount denominator of 200**: `JB721Constants.DISCOUNT_DENOMINATOR = 200`, so `discountPercent=200` means 100% off (free mint). The `cannotIncreaseDiscountPercent` tier flag prevents the owner from raising the discount after deployment -- decreasing is always allowed.

6. **Split fund distribution with try-catch**: All external calls during split distribution (to split hooks, terminals, and beneficiaries) are wrapped in try-catch. A reverting recipient does not brick payments for the entire project.

## Extension Points

| Point | Interface | Purpose |
|-------|-----------|---------|
| Token URI resolver | `IJB721TokenUriResolver` | Custom metadata rendering |
| Pay hook | `IJBPayHook` | Called after payment recorded |
| Cash out hook | `IJBCashOutHook` | Called during cash out |

## Dependencies
- `@bananapus/core-v6` — Core protocol interfaces
- `@bananapus/ownable-v6` — JB-aware ownership
- `@bananapus/address-registry-v6` — Deterministic deploy addresses
- `@bananapus/permission-ids-v6` — Permission constants
- `@openzeppelin/contracts` — ERC-721 utils, Ownable
- `@prb/math` — mulDiv
- `solady` — LibClone
