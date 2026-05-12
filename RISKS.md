# Juicebox 721 Hook Risk Register

This file covers the tiered-NFT accounting, reserve-mint, and cash-out risks in the shared 721 hook used across multiple higher-level products.

## How To Use This File

- Read `Priority risks` first. They summarize the shared 721-hook risks with the widest blast radius.
- Use the later sections for reentrancy, gas, tier accounting, and integration reasoning.
- Treat `Invariants to verify` as required coverage for any hook or store change.

## Priority Risks

| Priority | Risk | Why it matters | Primary controls |
|----------|------|----------------|------------------|
| P0 | Shared store corruption or accounting drift | `JB721TiersHookStore` is reused across products. A tier-accounting bug can affect many repos at once. | Heavy store testing, invariants, and cautious deployment review. |
| P1 | Gas and iteration ceilings around tier state | Tier operations can iterate over reserves, pricing state, and cash-out weights. | Gas tests, tier-count limits, and DoS review. |
| P1 | Cash-out and reserve math mismatch | Fair redemption depends on tier supply, pending reserves, and pricing state staying aligned. | Detailed invariants, fuzzing, and integration tests. |

## 1. Trust Assumptions

- **The store is trusted.** It keys state by `msg.sender`, so a hook can only affect its own namespace, but that namespace is fully trusted.
- **Tier configuration is partly immutable.** Price, supply, reserve frequency, category, voting units, and split percent are permanent after creation.
- **Category ordering matters.** The store's linked-list assumptions depend on correct sorted insertion.
- **`useReserveBeneficiaryAsDefault` has wide effects.** Setting it on a new tier can change the default reserve beneficiary for older tiers without their own explicit beneficiary.
- **Clone initialization is one-shot.** Clones are deployed and initialized atomically.
- **Directory and prices are trusted.** Terminal authentication and cross-currency behavior depend on core.

## 2. Economic Risks

- **Cash-out weight uses full undiscounted price.**
- **Pending reserves inflate the cash-out denominator before reserves are minted.**
- **Pay credits can accumulate without a cap.**
- **Zero-price tiers are valid.**
- **Discount math uses a denominator of 200, not 10,000.**
- **Currency mismatch skips minting when no prices contract is configured.** Funds land in project balance; see §8.3.
- **`splitPercent` can reduce fungible-token minting weight.**
- **Reserve minting is permissionless.**

## 3. Reentrancy Surface

- **Split hook callbacks execute arbitrary code.**
- **Split beneficiary ETH sends can fail softly and reroute value.**
- **Terminal `pay` and `addToBalanceOf` calls during split distribution can reenter external systems.**
- **Split fallback can still strand value if the project terminal rejects leftovers.**
- **There is no `ReentrancyGuard`.** Safety depends on state ordering, terminal auth, and wrapped external calls.

## 4. Gas And DoS Vectors

- **`totalCashOutWeight` iterates all tier IDs.**
- **`balanceOf`, `votingUnitsOf`, and `totalSupplyOf` also iterate all tiers.**
- **Large tier catalogs are technically allowed but not the supported operating shape.**
- **`tiersOf` still traverses removed tiers until cleanup runs.**
- **Minting across many tiers in one payment can get expensive fast.**
- **Reserve minting is loop-based and should be batched when large.**

## 5. Access Control

- **`adjustTiers` is permissioned and respects append-only restrictions.**
- **`mintFor` is permissioned and still depends on per-tier owner-mint flags.**
- **`setDiscountPercentOf` is permissioned and can be one-way constrained.**
- **`setMetadata` is permissioned and changes name, symbol, URIs, resolver, and tier URIs.**
- **Transfer pause is tier-sensitive.**
- **`mintPendingReservesFor` and `cleanTiers` are permissionless by design.**

## 6. Integration Risks

- **Hook weight can override fungible-token minting.**
- **Metadata encoding is fragile.**
- **`beforeCashOutRecordedWith` rejects mixed fungible-token cash outs.**
- **Split group IDs are tightly coupled to the hook address.**
- **ERC-20 split distribution depends on terminal allowance behavior.**
- **Forwarded funds with empty hook metadata can skip distribution and remain in the hook.**
- **Token URI resolver calls can block metadata reads if the resolver reverts.**

## 7. Invariants To Verify

- per-tier supply conservation holds
- total cash-out weight stays consistent with outstanding NFTs and pending reserves
- reserve minting stays bounded by reserve frequency
- token IDs remain unique
- credits track leftovers correctly
- removed tiers stay excluded from active listings
- store balance views match ERC-721 balances
- discount monotonicity is enforced when locked

## 8. Accepted Behaviors

### 8.1 Pending reserves dilute cash-out value before minting

This is intentional. Including pending reserves in the denominator prevents reserve front-running.

### 8.2 Cash-out weight uses full price regardless of discount

This is intentional. The cash-out weight represents treasury share, not purchase price.

### 8.3 Unsupported-currency payments are accepted as project balance and skip NFT minting

When a payment currency differs from the tier pricing currency and `PRICES == address(0)`, `JB721TiersHookLib.normalizePaymentValue` returns `valid = false` and `JB721TiersHook._processPayment` returns early — no NFT is minted, no credits accrue, no splits are forwarded, and the terminal keeps the payment in the project's balance.

This is intentional, not fail-open, for two reasons:

1. **Acceptance is opt-in by the project owner.** The terminal only finalizes the payment if the owner has explicitly added the currency to the terminal's accounting contexts via `addAccountingContextsFor`. The owner is saying "this project accepts funds in this currency." The 721 hook's job is to mint NFTs against payments it can price; the project's job is to receive funds in currencies it has opted into. These are decoupled by design.
2. **Reverting would be less reversible than the current behavior.** Letting payments land at the project preserves donation-style flows (project keeps the funds and can refund manually if it wants). A revert would kill those flows globally, including legitimate cases like accepting a currency before its price feed is wired.

Frontends and integrators should warn payers when they are about to pay in a currency the hook cannot price into tier units. Project owners who want NFT-bearing payments to fail atomically should either remove unsupported currencies from their terminal's accounting contexts or configure `PRICES` for all supported pairs.

### 8.4 Tiny split allocations can round down to zero

Dust-sized split allocations can become economically lossy after rounding.

### 8.5 Failed split payouts only degrade cleanly if the fallback terminal path works

If both the primary split path and the fallback `addToBalanceOf` path fail, the hook can retain assets with no built-in rescue path.

### 8.6 Credit-funded tier purchases may underfund split obligations

Pay credits can be used to buy tiers that carry a `splitPercent`. When credits satisfy part of the tier price, the fresh ETH forwarded to splits may be less than the split obligation implied by the full tier price. Project owners who consider this a problem should enable the `preventBuyingTierWithCredits` flag on affected tiers. This is accepted behavior.

### 8.7 Changing the default reserve beneficiary redirects pending reserves

When the default reserve beneficiary is updated, any pending (unminted) reserves across all tiers that rely on the default will be distributed to the new beneficiary once minted. This is by design — the project owner controls reserve distribution targets and may intentionally redirect pending reserves by updating the default.

### 8.8 Discounted credit mints retain full cash-out weight

Tokens minted at a discounted price via credits still carry the full undiscounted tier price as their cash-out weight. This means a holder who purchased at a discount receives the same treasury share as a holder who paid full price. Project owners should factor this into discount percentage decisions, as aggressive discounts can create favorable cash-out economics for discounted buyers.
