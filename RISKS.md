# Juicebox 721 Hook Risk Register

This file covers the tiered-NFT accounting, reserve-mint, and cash-out risks in the shared 721 hook used across multiple higher-level products.

## How to use this file

- Read `Priority risks` first. They summarize the shared 721-hook risks with the widest blast radius.
- Use the later sections for reentrancy, gas, tier accounting, and integration reasoning.
- Treat `Invariants to verify` as required coverage for any hook or store change.

## Priority risks

| Priority | Risk | Why it matters | Primary controls |
|----------|------|----------------|------------------|
| P0 | Shared store corruption or accounting drift | `JB721TiersHookStore` is reused across products. A tier-accounting bug can affect many repos at once. | Heavy store testing, invariants, and cautious deployment review. |
| P1 | Gas and iteration ceilings around tier state | Tier operations can iterate over reserves, pricing state, and cash-out weights. | Gas tests, tier-count limits, and DoS review. |
| P1 | Cash-out and reserve math mismatch | Fair redemption depends on tier supply, pending reserves, and pricing state staying aligned. | Detailed invariants, fuzzing, and integration tests. |

## 1. Trust assumptions

- **The store is trusted.** It keys state by `msg.sender`, so a hook can only affect its own namespace, but that namespace is fully trusted.
- **Tier configuration is partly immutable.** Price, supply, reserve frequency, category, voting units, and split percent are permanent after creation.
- **Category ordering matters.** The store's linked-list assumptions depend on correct sorted insertion.
- **`useReserveBeneficiaryAsDefault` has wide effects.** Setting it on a new tier can change the default reserve beneficiary for older tiers without their own explicit beneficiary.
- **Reserve-beneficiary defaulting is array-order-sensitive.** `recordAddTiers` validates each tier strictly in array order and only consults `defaultReserveBeneficiaryOf` as written by *earlier* tiers in the same batch (`JB721TiersHookStore.sol:1027-1032`, default written at `:1069-1077`). A tier with `reserveFrequency > 0` and no tier-specific `reserveBeneficiary` placed *before* the tier that sets `useReserveBeneficiaryAsDefault: true` reverts `JB721TiersHookStore_MissingReserveBeneficiary(tierId)`, even though a later tier sets the default. Because tiers must be sorted by ascending category, you cannot always reorder freely — so each reserve tier must either carry its own `reserveBeneficiary`, or appear after the tier that sets the default.
- **Clone initialization is one-shot.** Clones are deployed and initialized atomically.
- **Directory and prices are trusted.** Terminal authentication and cross-currency behavior depend on core.

## 2. Economic risks

- **Cash-out weight uses full undiscounted price.**
- **Pending reserves inflate the cash-out denominator before reserves are minted.**
- **Pay credits can accumulate without a cap.**
- **Zero-price tiers are valid.**
- **Discount math uses a denominator of 200, not 10,000.**
- **Currency mismatch skips minting when no prices contract is configured.** Funds land in project balance; see §8.3.
- **`splitPercent` can reduce fungible-token minting weight.**
- **Reserve minting is permissionless.**

## 3. Reentrancy surface

- **Split hook callbacks execute arbitrary code.**
- **Split beneficiary ETH sends can fail softly and reroute value.**
- **Terminal `pay` and `addToBalanceOf` calls during split distribution can reenter external systems.**
- **Split fallback can still strand value if the project terminal rejects leftovers.**
- **There is no `ReentrancyGuard`.** Safety depends on state ordering, terminal auth, and wrapped external calls.

## 4. Gas and DoS vectors

- **`totalCashOutWeightOf` and `balanceOf` are O(1).** Both read running aggregates maintained on mint/burn/transfer
  rather than iterating tiers, so cash-out pricing and balance reads cannot be gas-DoS'd by inflating the tier count
  (e.g. via delegated tier creation through Croptop).
- **`votingUnitsOf` and delegation tier activation are bounded by bitmap words plus held-tier count.** The store
  maintains per-owner held-tier bitmap words on ownership transitions, updating one bitmap word when an account enters
  or exits a tier. Reads scan one storage word per 256 tier IDs (at most 256 words at the `uint16` tier cap) plus the
  owner's held tiers, so they do not walk every tier ID.
- **`hasTiersOfAt` is backed by checkpointed tier balances.** The checkpoint module writes per-account tier-balance
  traces on ownership transitions so membership checks scale with the queried tier array, not with minted token count.
  Empty tier arrays fail closed, and future-block queries revert.
- **`totalSupplyOf` still iterates all tiers.** This is not on the cash-out fund-stranding path, but very large tier
  catalogs can still make total-supply reads expensive.
- **Large tier catalogs are technically allowed but not the supported operating shape.**
- **`tiersOf` still traverses removed tiers until cleanup runs.** `cleanTiers` compacts removed tiers out of the
  sorted traversal path, including removed trailing tiers when at least one active tier remains.
- **Minting across many tiers in one payment can get expensive fast.**
- **Reserve minting is loop-based and should be batched when large.**

## 5. Access control

- **`adjustTiers` is permissioned and respects append-only restrictions.**
- **`mintFor` is permissioned free NFT issuance.** It still depends on per-tier `allowOwnerMint`, but it bypasses price, credits, and `cantBuyWithCredits`, consumes tier supply, and should be treated as supply-admin authority.
- **`setDiscountPercentOf` is permissioned and can be one-way constrained.** The `cantIncreaseDiscountPercent` per-tier flag makes the discount monotonically non-increasing once set.
- **`setMetadata` is permissioned and changes name, symbol, URIs, resolver, and tier URIs.**
- **Transfer pause is tier-sensitive.**
- **`mintPendingReservesFor` and `cleanTiers` are permissionless by design.**

## 6. Integration risks

- **Hook weight can override fungible-token minting.**
- **Metadata encoding is fragile.** Pay-hook metadata carries `(beneficiary, payer, splitData, splitCreditWeight)`.
  The local hook consumes the first three values and downstream composers may consume the appended split-credit value.
- **`beforeCashOutRecordedWith` rejects mixed fungible-token cash outs.**
- **Split group IDs are tightly coupled to the hook address.**
- **ERC-20 split distribution depends on terminal allowance behavior.**
- **Forwarded funds must match split metadata.** The pay hook rejects native `msg.value` mismatches, non-native calls
  carrying ETH, missing split metadata for nonzero forwarded amounts, and split metadata whose amounts do not sum to
  the forwarded amount.
- **Token URI resolver calls can block metadata reads if the resolver reverts.**

## 7. Invariants to verify

- per-tier supply conservation holds
- total cash-out weight stays consistent with outstanding NFTs and pending reserves
- reserve minting stays bounded by reserve frequency
- token IDs remain unique
- credits track leftovers correctly
- removed tiers stay excluded from active listings
- `cleanTiers` moves the sorted-list end back when a trailing tier is removed
- store balance views match ERC-721 balances
- discount monotonicity is enforced when locked

## 8. Accepted behaviors

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

Pay credits can be used to buy tiers that carry a `splitPercent`. When credits satisfy part of the tier price, the fresh ETH forwarded to splits may be less than the split obligation implied by the full tier price. Project owners who consider this a problem should enable the `cantBuyWithCredits` flag on affected tiers. This is accepted behavior.

### 8.7 Changing the default reserve beneficiary redirects pending reserves

When the default reserve beneficiary is updated, any pending (unminted) reserves across all tiers that rely on the default will be distributed to the new beneficiary once minted. This is by design — the project owner controls reserve distribution targets and may intentionally redirect pending reserves by updating the default.

### 8.8 Discounted credit mints retain full cash-out weight

Tokens minted at a discounted price via credits still carry the full undiscounted tier price as their cash-out weight. This means a holder who purchased at a discount receives the same treasury share as a holder who paid full price. Project owners should factor this into discount percentage decisions, as aggressive discounts can create favorable cash-out economics for discounted buyers.

### 8.9 Tier removal does not cancel already accrued reserve or cash-out weight

Removing a tier prevents future paid and owner mints from that tier, but existing NFTs keep their cash-out weight and pending reserves remain part of `totalCashOutWeightOf`. Project owners should treat tier removal as a listing control, not as a way to erase reserve obligations or cash-out denominator effects.

### 8.10 Future tier URI entries are controlled by metadata permissions

`setMetadata` can set an encoded URI for a tier ID before that tier is added. If a later tier is created with an empty encoded URI at that ID, it inherits the pre-set value. This is permissioned by `SET_721_METADATA`, so delegates with metadata authority can affect future tier presentation as well as existing metadata.
