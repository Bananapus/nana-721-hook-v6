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

#### Split Amount and Price Normalization

Tiers can be priced in a different currency than the payment token (e.g. tiers priced in USD while payments arrive in ETH). The split/weight pipeline in `beforePayRecordedWith` resolves this in two steps:

1. **`calculateSplitAmounts`** — For each tier the payer wants to mint, looks up its `splitPercent` (the fraction of the tier price that should be routed to the tier's split group rather than into the project treasury). Computes `effectivePrice * splitPercent / SPLITS_TOTAL_PERCENT` for each tier, where `effectivePrice` accounts for any active discount. Returns the total and a per-tier breakdown, all denominated in the **tier pricing currency**.

2. **`convertSplitAmounts`** — If the payment currency differs from the tier pricing currency, converts every per-tier split amount (and the total) into the **payment token denomination** using `JBPrices`. This is necessary because the terminal will subtract the split amount from the payment value, so both must be in the same unit.

After conversion, `calculateWeight` scales the terminal's minting weight down by the fraction of the payment that was routed to splits (unless the `issueTokensForSplits` flag is set, in which case the full weight is preserved).

During `afterPayRecordedWith`, the payment value is separately normalized into the tier pricing currency via `normalizePaymentValue` so that tier prices can be compared against what was paid. The forwarded split funds are then distributed to each tier's split group by `distributeAll`.

### Discount Mechanism

Each tier has a `discountPercent` (0-200 scale where 200 = 100% discount / free mint). The project owner can adjust it via `setDiscountPercentOf`, subject to a per-tier `cannotIncreaseDiscountPercent` flag that prevents raising the discount once set. Discounts can only be decreased unless the tier explicitly allows increases.

Key behaviors:
- **Minting**: The store applies the discount when checking the price during `recordMint`, so payers pay less.
- **Split calculations**: `calculateSplitAmounts` applies the discount to the tier price before computing the split portion, so splits are proportional to the actual amount paid.
- **Cash-out weight**: Uses the **original undiscounted price**, not the effective price. This means a discounted NFT carries the same cash-out weight as a full-price one. Project owners should be aware that heavily discounted mints dilute the cash-out pool at full weight while contributing less to the treasury.

### NFT Cash Out
```
Holder → JBMultiTerminal.cashOutTokensOf()
  → JB721TiersHook.afterCashOutRecordedWith()
    → Burn specified NFT token IDs
    → Each NFT's cash-out weight = tier.price (full price, ignoring discounts)
    → Total cash-out weight (denominator) = sum of (tier.price * (outstanding + pending)) across all tiers
    →   where outstanding = minted - burned, pending = pending reserve mints
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

## Design Decisions

1. **Clone-based deployment** — `JB721TiersHookDeployer` uses Solady's `LibClone` to deploy minimal proxies of a reference `JB721TiersHook` instance. This keeps deployment cost low and consistent regardless of the hook contract's bytecode size. Each clone is initialized via `initialize()` (not a constructor), which sets the project ID, tiers, and flags. Deterministic deploys are supported via `cloneDeterministic` with a caller-scoped salt.

2. **Separate store contract** — `JB721TiersHookStore` holds all tier data, mint tracking, and pricing logic in a standalone contract shared across hook instances. This serves two purposes: it keeps the hook contract under the EIP-170 size limit (24 KB), and it allows the store to act as the `msg.sender` for state mutations (tier additions use `msg.sender` as the hook key), providing a natural access-control boundary.

3. **Category sorting instead of price sorting** — Tiers are stored in a linked list sorted by `category` (a uint24 grouping field), not by price. This lets projects organize NFTs into logical groups (e.g. membership tiers, collectibles, special editions) and query them by group. The `InvalidCategorySortOrder` error enforces that new tiers are added in non-decreasing category order.

4. **Cash-out weight uses `initialSupply * price`** — The `totalCashOutWeight` denominator sums `price * (outstanding + pendingReserves)` across all tiers, where outstanding = minted minus burned. Each individual NFT's weight is simply its tier's `price`. Using the original undiscounted price (rather than what was actually paid) ensures that cash-out values are stable and predictable: discounts are treated as transient purchase incentives, not permanent reductions in an NFT's share of the treasury.

5. **Library extraction for EIP-170 compliance** — `JB721TiersHookLib` contains split calculations, price normalization, fund distribution, tier adjustment logic, and IPFS URI decoding. These are called via `external` library functions (which deploy as a separate contract) or via `DELEGATECALL`. This pattern keeps the hook contract's deployed bytecode under the 24 KB limit while preserving the ability to emit events from the hook's address.

6. **Discount denominator of 200** — The `discountPercent` field is a uint8 with a denominator of 200 (`JB721Constants.DISCOUNT_DENOMINATOR`). A value of 200 represents 100% discount (free mint), giving 0.5% granularity. The `cannotIncreaseDiscountPercent` flag on each tier lets project owners create promotional discounts that can be reduced but never increased beyond their initial level.

7. **Split fund distribution with try-catch** — All external calls during split distribution (to split hooks, terminals, and beneficiaries) are wrapped in try-catch. A reverting recipient does not brick payments for the entire project.

## Dependencies
- `@bananapus/core-v6` — Core protocol interfaces
- `@bananapus/ownable-v6` — JB-aware ownership
- `@bananapus/address-registry-v6` — Deterministic deploy addresses
- `@bananapus/permission-ids-v6` — Permission constants
- `@openzeppelin/contracts` — ERC-721 utils, Ownable
- `@prb/math` — mulDiv
- `solady` — LibClone
