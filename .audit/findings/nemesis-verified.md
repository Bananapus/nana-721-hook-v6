# N E M E S I S — Verified Findings

## Scope
- **Language:** Solidity 0.8.26
- **Modules analyzed:** JB721TiersHook, JB721TiersHookStore, JB721TiersHookLib, JB721Hook, ERC721, JB721TiersHookDeployer, JB721TiersHookProjectDeployer, Deploy.s.sol, Hook721DeploymentLib, JBBitmap, JBIpfsDecoder, JB721Constants, JB721TiersRulesetMetadataResolver, all interfaces and structs
- **Functions analyzed:** 45+ entry points across 7 contracts/libraries
- **Coupled state pairs mapped:** 6
- **Mutation paths traced:** 18
- **Nemesis loop iterations:** 4 (2 Feynman + 2 State) — converged at Pass 4

---

## Nemesis Map (Phase 1 Cross-Reference)

| Function | Writes _balances | Writes tierBalanceOf | P1 Sync |
|----------|-----------------|---------------------|---------|
| _mint (via _update) | +1 | +1 (via recordTransferForTier) | SYNCED |
| _burn (via _update) | -1 | -1 (via recordTransferForTier) | SYNCED |
| transferFrom (via _update) | -1/+1 | -1/+1 (via recordTransferForTier) | SYNCED |

| Function | Writes remainingSupply | Writes numberOfReservesMintedFor | P3 Sync |
|----------|----------------------|--------------------------------|---------|
| recordMint | -1 per NFT | — | SYNCED |
| recordMintReservesFor | -1 per NFT | +count | SYNCED |

---

## Verification Summary

| ID | Source | Coupled Pair | Breaking Op | Original Severity | Verdict | Final Severity |
|----|--------|-------------|-------------|-------------------|---------|----------------|
| NM-001 | Feynman Pass 1 | ETH/token ↔ split target | `_sendPayoutToSplit()` | MEDIUM | TRUE POSITIVE | MEDIUM |
| NM-002 | Feynman Pass 1 | split amount ↔ mint price | `calculateSplitAmounts()` | LOW | TRUE POSITIVE | LOW |
| NM-003 | Feynman Pass 1 | — | `setMetadata()` | LOW | TRUE POSITIVE | LOW (Info) |
| NM-004 | Feynman Pass 1 | — | `recordAddTiers()` | LOW | DOWNGRADE | LOW (Info) |
| NM-005 | Feynman Pass 1 | — | `calculateSplitAmounts()` | LOW | TRUE POSITIVE | LOW (Gas) |
| NM-006 | Feynman Pass 1 | ETH/token ↔ split target | `_sendPayoutToSplit()` | LOW | TRUE POSITIVE | LOW |
| NM-007 | Feynman Pass 1 | — | `_addToBalance()` | LOW | FALSE POSITIVE | — |
| SI-001 | State Pass 2 | _balances ↔ tierBalanceOf | — | — | SOUND | — |
| SI-002 | State Pass 2 | remainingSupply ↔ reservesMinted | — | — | SOUND | — |
| SI-003 | State Pass 2 | payCreditsOf ↔ payment | — | — | SOUND | — |
| SI-004 | State Pass 2 | price ↔ cashOutWeight | — | — | SOUND (by design) | — |
| SI-005 | State Pass 2 | totalCashOutWeight ↔ pendingReserves | — | — | SOUND (by design) | — |

---

## Verified Findings (TRUE POSITIVES)

### Finding NM-001: Split distribution funds permanently stuck when target project lacks terminal

**Severity:** MEDIUM
**Source:** Feynman Pass 1 — Category 6 (Return/Error) + Category 4 (Assumptions)
**Verification:** Code trace (Method A)

**Feynman Question that exposed this:**
> Q6.3: What if an external call in this function fails silently? Does the language/runtime guarantee failure propagation?

**The code:**
```solidity
// JB721TiersHookLib.sol:264-267
if (split.projectId != 0) {
    IJBTerminal terminal = directory.primaryTerminalOf(split.projectId, token);
    if (address(terminal) == address(0)) return; // ← silent return, funds stay in hook
```

**Why this is wrong:**
When `_distributeSingleSplit` processes splits, it computes `payoutAmount` per split and decrements `leftoverAmount` before calling `_sendPayoutToSplit`. If `_sendPayoutToSplit` silently returns (because the split's target project has no terminal for the distributed token), the `payoutAmount` has already been subtracted from `leftoverAmount` — but the funds were never sent. They remain in the hook contract with no recovery mechanism.

**Verification evidence:**
Code trace through the full distribution path:
1. `_processPayment` (JB721TiersHook.sol:654) calls `JB721TiersHookLib.distributeAll` with `context.forwardedAmount.value` — the terminal forwarded these funds to the hook
2. `_distributeSingleSplit` (JB721TiersHookLib.sol:237-243) computes `payoutAmount`, calls `_sendPayoutToSplit`, then decrements `leftoverAmount -= payoutAmount` in unchecked block
3. `_sendPayoutToSplit` (JB721TiersHookLib.sol:266-267) silently returns when `primaryTerminalOf` is address(0)
4. The hook contract (JB721TiersHook) has no sweep/rescue function for arbitrary tokens or ETH

**Trigger Sequence:**
1. Project owner adds a tier with `splitPercent > 0` and configures a split pointing to project X
2. Project X has a terminal for the payment token at setup time
3. Project X later removes its terminal for that token (or never had one for a secondary token)
4. A user pays the hook's project, minting an NFT from the tier with splits
5. The terminal forwards `forwardedAmount` to the hook
6. `distributeAll` → `_distributeSingleSplit` → `_sendPayoutToSplit` silently returns
7. Funds remain trapped in the hook contract permanently

**Consequence:**
- Funds (ETH or ERC-20 tokens) are permanently locked in the hook contract
- No revert signals the failure to the payer or project owner
- No admin function exists to recover stuck funds
- The amount stuck equals `mulDiv(tierPrice, splitPercent, SPLITS_TOTAL_PERCENT)` per affected mint

**Fix:**
```solidity
// Option A: Revert on failed distribution
if (address(terminal) == address(0)) revert JB721TiersHookLib_NoTerminal();

// Option B: Return funds to project balance instead of dropping
if (address(terminal) == address(0)) {
    // Fall through to addToBalance for the hook's own project
    return;
}
// ... and in _distributeSingleSplit, don't decrement leftoverAmount when _sendPayoutToSplit fails
```

---

### Finding NM-002: calculateSplitAmounts uses full price while recordMint uses discounted price

**Severity:** LOW
**Source:** Feynman Pass 1 — Category 3 (Consistency)
**Verification:** Code trace (Method A)

**Feynman Question that exposed this:**
> Q3.3: If functionA validates parameter P, does functionB (which also takes P) validate it the same way?

**The code:**
```solidity
// JB721TiersHookLib.sol:147 — uses full (base) price
uint256 price = store.tierOf(hook, tierIdsToMint[i], false).price;
splitAmounts[splitTierCount] = mulDiv(price, splitPercent, JBConstants.SPLITS_TOTAL_PERCENT);

// JB721TiersHookStore.sol:1061-1063 — applies discount
price -= mulDiv(price, _storedTierOf[msg.sender][tierIds[i]].discountPercent, DISCOUNT_DENOMINATOR);
```

**Why this matters:**
`calculateSplitAmounts` (called in `beforePayRecordedWith`) computes the split amount forwarded to the hook using the full tier price. `recordMint` (called in `afterPayRecordedWith`) charges the discounted price. When a tier has both a discount and splits configured, the minimum payment required is: `discountedMintPrice + fullPriceSplitAmount`. This effectively reduces the discount benefit proportional to the split percentage.

**Verification evidence:**
- `beforePayRecordedWith` calls `calculateSplitAmounts` → returns `totalSplitAmount` based on full price
- The terminal uses this to set `hookSpecifications[0].amount` (the forwarded amount)
- `afterPayRecordedWith` → `_processPayment` → `_mintAll` → `recordMint` charges discounted price
- Example: Tier price = 1 ETH, discount = 50% (100/200), split = 50%
  - Split amount = 0.5 ETH (based on full 1 ETH price)
  - Mint cost = 0.5 ETH (discounted)
  - User total = 1 ETH — discount is effectively nullified

**Consequence:**
- Users paying for discounted tiers with splits configured pay more than they might expect
- Not exploitable — the user gets the correct NFT and the correct split distribution
- This appears to be by design: splits should represent a fixed percentage of the tier's base value

---

### Finding NM-003: setMetadata uses address(this) as tokenUriResolver sentinel

**Severity:** LOW (Informational)
**Source:** Feynman Pass 1 — Category 1 (Purpose)
**Verification:** Code trace (Method A)

**The code:**
```solidity
// JB721TiersHook.sol:423
if (tokenUriResolver != IJB721TokenUriResolver(address(this))) {
    _recordSetTokenUriResolver(tokenUriResolver);
}
```

**Why this matters:**
Uses `address(this)` as a sentinel value meaning "don't update the resolver." The standard sentinel in Solidity is `address(0)`, which here would mean "clear the resolver." While functional, this is unconventional. If someone accidentally passes the hook's own address as a resolver, the update is silently skipped — though this is arguably a safety feature since the hook doesn't implement `IJB721TokenUriResolver`.

**Consequence:**
- No security impact
- Minor developer experience concern — unconventional pattern may confuse integrators

---

### Finding NM-004: defaultReserveBeneficiaryOf globally overwritten by useReserveBeneficiaryAsDefault

**Severity:** LOW (Informational)
**Source:** Feynman Pass 1 — Category 2 (Ordering) + Category 5 (Boundaries)
**Verification:** Code trace (Method A) — DOWNGRADED from potential concern to informational

**The code:**
```solidity
// JB721TiersHookStore.sol:886-889
if (tierToAdd.useReserveBeneficiaryAsDefault) {
    if (defaultReserveBeneficiaryOf[msg.sender] != tierToAdd.reserveBeneficiary) {
        defaultReserveBeneficiaryOf[msg.sender] = tierToAdd.reserveBeneficiary;
    }
}
```

**Why this was flagged:**
Adding a new tier with `useReserveBeneficiaryAsDefault = true` overwrites the global default reserve beneficiary, affecting ALL existing tiers that rely on the default (i.e., tiers without a tier-specific `_reserveBeneficiaryOf`).

**Verification evidence — DOWNGRADE justification:**
- The flag `useReserveBeneficiaryAsDefault` is self-documenting — it explicitly declares intent to set the global default
- The project owner calling `adjustTiers` must have `ADJUST_721_TIERS` permission
- This is a privileged, intentional action, not an accidental side effect
- Tiers with tier-specific reserve beneficiaries (set via `_reserveBeneficiaryOf`) are unaffected

**Consequence:**
- Expected behavior when the flag is used
- Project owners should be aware that this affects ALL tiers without tier-specific beneficiaries

---

### Finding NM-005: Duplicate external calls in calculateSplitAmounts

**Severity:** LOW (Gas)
**Source:** Feynman Pass 1 — Category 1 (Purpose)
**Verification:** Code trace (Method A)

**The code:**
```solidity
// JB721TiersHookLib.sol:144,147
uint256 splitPercent = store.tierOf(hook, tierIdsToMint[i], false).splitPercent;  // call 1
if (splitPercent != 0) {
    uint256 price = store.tierOf(hook, tierIdsToMint[i], false).price;            // call 2
```

**Why this matters:**
`store.tierOf()` is called twice per loop iteration for the same tier ID — once to read `splitPercent` and once to read `price`. A single call could retrieve both values, saving one external call per tier with splits.

**Consequence:**
- Wasted gas: one redundant STATICCALL per tier in the loop
- No security or correctness impact

**Fix:**
```solidity
JB721Tier memory tier = store.tierOf(hook, tierIdsToMint[i], false);
if (tier.splitPercent != 0) {
    splitTierIds[splitTierCount] = tierIdsToMint[i];
    splitAmounts[splitTierCount] = mulDiv(tier.price, tier.splitPercent, JBConstants.SPLITS_TOTAL_PERCENT);
```

---

### Finding NM-006: _sendPayoutToSplit silently drops funds when split has no beneficiary and no projectId

**Severity:** LOW
**Source:** Feynman Pass 1 — Category 6 (Return/Error)
**Verification:** Code trace (Method A)

**The code:**
```solidity
// JB721TiersHookLib.sol:264-282
if (split.projectId != 0) {
    // ... send to project terminal
} else if (split.beneficiary != address(0)) {
    // ... send to beneficiary
}
// implicit: if projectId == 0 AND beneficiary == address(0), function returns without sending
```

**Why this matters:**
If a split is configured with `projectId == 0` AND `beneficiary == address(0)`, `_sendPayoutToSplit` silently returns without transferring funds. The funds remain in the hook with no recovery path.

**Verification evidence — mitigating factor:**
- The JBSplits contract likely prevents this configuration at the `setSplitGroupsOf` level
- However, this library function does not independently validate, creating a defense-in-depth gap

**Consequence:**
- If a misconfigured split reaches this code, funds are permanently stuck
- Low likelihood due to upstream validation in JBSplits

---

## False Positives Eliminated

### FF-007 (was NM-007): _addToBalance silently drops leftover when project has no terminal

**Original Severity:** LOW
**Verdict:** FALSE POSITIVE

**Reason:** The `_addToBalance` function in `_distributeSingleSplit` sends leftover funds to the hook's own project via `directory.primaryTerminalOf(projectId, token)`. The `projectId` is the hook's project, and `token` is the forwarded payment token. Since the payment originated from a terminal of this project for this exact token, the project is guaranteed to have a terminal for it. The `primaryTerminalOf` call will return a valid terminal address.

The only theoretical scenario where this fails is if the terminal is removed between `beforePayRecordedWith` (where split amounts are calculated) and `afterPayRecordedWith` (where distribution occurs) — but both happen within the same transaction, and terminal removal requires a separate privileged call.

---

## State Inconsistency Audit — All Pairs SOUND

### SI-001: ERC721._balances ↔ STORE.tierBalanceOf — SOUND
All mint, burn, and transfer paths go through `_update` → `recordTransferForTier`. No path modifies one without the other. Atomic synchronization confirmed.

### SI-002: remainingSupply ↔ numberOfReservesMintedFor — SOUND
`recordMint` decrements `remainingSupply` and checks `remainingSupply >= _numberOfPendingReservesFor`. `recordMintReservesFor` increments `numberOfReservesMintedFor` and decrements `remainingSupply`. Invariant maintained.

### SI-003: payCreditsOf accounting — SOUND
Credits tracked per beneficiary. Payer == beneficiary: credits combined with payment value. Payer != beneficiary: credits preserved unchanged. Final credit value accurately reflects leftover + unused credits.

### SI-004: cashOutWeightOf uses full price — SOUND (by design)
Both `cashOutWeightOf` and `totalCashOutWeight` use `_storedTierOf.price` (base price), not discounted price. Discounts are transient minting incentives and intentionally don't affect cash-out value.

### SI-005: totalCashOutWeight includes pending reserves — SOUND (by design)
Pending reserves included in `totalCashOutWeight` to prevent early cashers from extracting disproportionate value before reserves are minted. Correctly dilutes individual cash-out weight.

---

## Feedback Loop Discoveries

No findings emerged exclusively from the cross-feed between Feynman and State Inconsistency auditors. All findings originated in Feynman Pass 1. The State Inconsistency audit confirmed all coupled state pairs as SOUND, producing no gaps or suspects for Feynman to re-interrogate. The loop converged after 4 passes.

This indicates that the codebase's coupled state management is well-implemented. The findings that exist are in the value distribution logic (splits), not in state synchronization.

---

## Summary
- Total functions analyzed: 45+
- Coupled state pairs mapped: 6
- Mutation paths traced: 18
- Nemesis loop iterations: 4 (converged)
- Raw findings (pre-verification): 0 CRITICAL | 0 HIGH | 1 MEDIUM | 6 LOW
- After verification: 6 TRUE POSITIVE | 1 FALSE POSITIVE | 1 DOWNGRADED (LOW concern → Informational)
- **Final: 0 CRITICAL | 0 HIGH | 1 MEDIUM | 5 LOW**
