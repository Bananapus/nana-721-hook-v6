# nana-721-hook-v6 — Architecture

## Purpose

NFT tier system for Juicebox V6. Allows projects to attach tiered NFT minting to payments and use NFTs as cash-out hooks. Supports on-chain and off-chain metadata, category-based sorting, and configurable pricing with discounts.

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
│   └── JB721TiersHookLib.sol         — Split calculations, price normalization, weight math, fund distribution
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
  → afterPayRecordedWith()
    → Decode tier IDs from metadata
    → For each tier:
      → Validate: not removed, not paused, supply available
      → Check price (with optional discount, normalized to tier pricing currency)
      → Mint NFT to beneficiary
    → Distribute split funds to tier split recipients
    → Leftover amount optionally mints best-available tiers
```

### NFT Cash Out
```
Holder → JBMultiTerminal.cashOutTokensOf()
  → JB721TiersHook.afterCashOutRecordedWith()
    → Burn specified NFT token IDs
    → Each NFT's cash-out weight contributes to reclaim amount
    → Weight = tier.initialQuantity * tier.price (or custom)
```

### Tier Management
```
Owner → JB721TiersHook.adjustTiers()
  → Add new tiers (must be sorted by category)
  → Remove existing tiers (flags, doesn't delete)
```

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
- `solady` — LibString, Base64
