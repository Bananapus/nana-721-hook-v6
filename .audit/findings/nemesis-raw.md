# N E M E S I S — Raw Findings (Pre-Verification)

## Phase 0: Attacker Recon

**Language:** Solidity 0.8.26

### Attack Goals (Q0.1)
1. **Drain/steal funds** from the project treasury via manipulated cash outs or split distributions
2. **Mint NFTs for free** or below-price (bypass payment requirements)
3. **Manipulate voting power** to control governance
4. **Grief other NFT holders** by diluting cash-out weight or manipulating reserves
5. **DoS critical operations** (minting, cash outs, transfers, split distributions)

### Novel Code (Q0.2)
- `JB721TiersHookStore` — complex tiered NFT accounting with sorted linked list, reserve frequency calculation, bitmap-based tier removal, packed bool storage
- `JB721TiersHookLib` — split distribution logic via DELEGATECALL, price normalization, split amount calculation from tier metadata
- `JB721TiersHook._processPayment` — credit system (payCreditsOf), overspending control, two-actor (payer/beneficiary) accounting

### Value Stores (Q0.3)
- `payCreditsOf[address]` — overpayment credits per address (JB721TiersHook)
  - Outflows: `_processPayment` (used during minting when payer==beneficiary)
- `tierBalanceOf[hook][owner][tierId]` — per-owner per-tier NFT balance (Store)
  - Outflows: `recordTransferForTier` (decrements on transfer/burn)
- ETH/tokens flowing through `distributeAll` → `_distributeSingleSplit` → `_sendPayoutToSplit`
  - Outflows: split beneficiary addresses, terminal.pay, terminal.addToBalance
- `_storedTierOf[hook][tierId]` — tier data including price, remainingSupply, initialSupply
  - Mutations: `recordAddTiers`, `recordMint`, `recordMintReservesFor`, `recordSetDiscountPercentOf`

### Complex Paths (Q0.4)
1. **Payment → Mint → Transfer tracking**: terminal → `afterPayRecordedWith` → `_processPayment` → `recordMint` → `_mint` → `_update` → `recordTransferForTier`
2. **Cash out → Burn → Weight recalculation**: terminal → `afterCashOutRecordedWith` → `_burn` → `_update` → `recordTransferForTier` → `_didBurn` → `recordBurn`
3. **Split calculation → Distribution**: `beforePayRecordedWith` → `calculateSplitAmounts` (view) → terminal forwards → `afterPayRecordedWith` → `distributeAll` → `_sendPayoutToSplit` → external calls

### Priority Order
1. **JB721TiersHookLib.distributeAll/calculateSplitAmounts** — value movement + external calls + complex calculation
2. **JB721TiersHook._processPayment** — credit accounting + minting + overspending
3. **JB721TiersHookStore.recordMint** — supply tracking + price validation + discount application
4. **JB721TiersHook._update** — transfer pause + first owner + balance tracking sync
5. **JB721TiersHookStore.totalCashOutWeight/cashOutWeightOf** — cash out value calculations

---

## Phase 1: Dual Mapping

### 1A: Function-State Matrix

| Function | Reads | Writes | Guards | External Calls |
|----------|-------|--------|--------|----------------|
| `initialize` | PROJECT_ID | PROJECT_ID, _packedPricingContext, baseURI, contractURI | PROJECT_ID==0 | STORE.recordAddTiers, STORE.recordFlags, STORE.recordSetTokenUriResolver |
| `adjustTiers` | owner() | (via lib) | _requirePermissionFrom(ADJUST_721_TIERS) | JB721TiersHookLib.adjustTiersFor (DELEGATECALL) |
| `mintFor` | owner() | (via STORE+_mint) | _requirePermissionFrom(MINT_721) | STORE.recordMint, _mint |
| `mintPendingReservesFor` | PROJECT_ID | (via STORE+_mint) | ruleset.mintPendingReservesPaused | STORE.recordMintReservesFor, STORE.reserveBeneficiaryOf, _mint |
| `setDiscountPercentOf` | owner() | (via STORE) | _requirePermissionFrom(SET_721_DISCOUNT_PERCENT) | STORE.recordSetDiscountPercentOf |
| `setMetadata` | owner() | baseURI, contractURI | _requirePermissionFrom(SET_721_METADATA) | STORE.recordSetTokenUriResolver, STORE.recordSetEncodedIPFSUriOf |
| `afterPayRecordedWith` | PROJECT_ID | payCreditsOf, (via STORE) | isTerminalOf(projectId, msg.sender) | _processPayment → STORE.recordMint, _mint, distributeAll |
| `afterCashOutRecordedWith` | PROJECT_ID | (via _burn+STORE) | isTerminalOf, msg.value==0 | _burn, STORE.recordBurn |
| `_update` | (tier from STORE) | _firstOwnerOf | transfersPaused check | STORE.tierOfTokenId, STORE.recordTransferForTier |
| `_processPayment` | _packedPricingContext, payCreditsOf, flags | payCreditsOf | overspending check | STORE.recordMint, _mint, distributeAll |

### Store Function-State Matrix

| Function | Reads | Writes | Guards |
|----------|-------|--------|--------|
| `recordAddTiers` | maxTierIdOf, _flagsOf, _lastTrackedSortedTierIdOf | _storedTierOf, maxTierIdOf, _tierIdAfter, _startingTierIdOfCategory, _reserveBeneficiaryOf, defaultReserveBeneficiaryOf, encodedIPFSUriOf, _tierVotingUnitsOf, _lastTrackedSortedTierIdOf | tier config validation |
| `recordMint` | _storedTierOf, _removedTiersBitmapWordOf | _storedTierOf.remainingSupply | tier removed check, price check, supply check |
| `recordMintReservesFor` | _storedTierOf, numberOfReservesMintedFor | numberOfReservesMintedFor, _storedTierOf.remainingSupply | pending reserves check |
| `recordBurn` | — | numberOfBurnedFor | none |
| `recordTransferForTier` | — | tierBalanceOf | none |
| `recordRemoveTierIds` | _storedTierOf.packedBools | _removedTiersBitmapWordOf | cannotBeRemoved check |
| `recordSetDiscountPercentOf` | _storedTierOf | _storedTierOf.discountPercent | bounds + cannotIncreaseDiscountPercent |

### 1B: Coupled State Dependency Map

| Pair | State A | State B | Invariant |
|------|---------|---------|-----------|
| P1 | ERC721._balances[owner] | STORE.tierBalanceOf[hook][owner][*] (sum) | Both must equal the number of NFTs owner holds |
| P2 | ERC721._owners[tokenId] | STORE.tierBalanceOf[hook][owner][tierId] | Ownership and balance must be consistent |
| P3 | _storedTierOf.remainingSupply | numberOfReservesMintedFor + numberOfBurnedFor | initialSupply = remainingSupply + minted (including reserves) + burned (reserves can overlap) |
| P4 | _storedTierOf.remainingSupply | _numberOfPendingReservesFor | remainingSupply must always be >= pending reserves |
| P5 | _storedTierOf.price | cashOutWeightOf / totalCashOutWeight | Cash out weight uses full price (not discounted) |
| P6 | payCreditsOf[beneficiary] | actual payment value | Credits must track leftover payment accurately |

### 1C: Cross-Reference (Nemesis Map)

| Function | Writes _balances | Writes tierBalanceOf | P1 Sync |
|----------|-----------------|---------------------|---------|
| _mint (via _update) | +1 | +1 (via recordTransferForTier) | SYNCED |
| _burn (via _update) | -1 | -1 (via recordTransferForTier) | SYNCED |
| transferFrom (via _update) | -1/+1 | -1/+1 (via recordTransferForTier) | SYNCED |
| recordBurn | — | — | N/A (only numberOfBurnedFor) |

| Function | Writes remainingSupply | Writes numberOfReservesMintedFor | P3 Sync |
|----------|----------------------|--------------------------------|---------|
| recordMint | -1 per NFT | — | SYNCED (non-reserve mint) |
| recordMintReservesFor | -1 per NFT | +count | SYNCED |
| recordBurn | — | — | numberOfBurnedFor incremented separately |

---

## Pass 1 (Feynman) — Raw Hypotheses

### FF-001: Split distribution funds permanently stuck when target project lacks terminal
**Severity:** MEDIUM
**Source:** Category 6 (Return/Error) + Category 4 (Assumptions)
**File:** `JB721TiersHookLib.sol:266-267`

`_sendPayoutToSplit` silently returns when `primaryTerminalOf(split.projectId, token) == address(0)`. But `leftoverAmount` was already decremented. The funds remain in the hook contract with no recovery mechanism.

### FF-002: calculateSplitAmounts uses full price, recordMint uses discounted price
**Severity:** LOW
**Source:** Category 3 (Consistency)
**Files:** `JB721TiersHookLib.sol:147` vs `JB721TiersHookStore.sol:1061-1063`

`calculateSplitAmounts` fetches `store.tierOf(hook, tierIdsToMint[i], false).price` (base price). `recordMint` applies discount: `price -= mulDiv(price, discountPercent, DISCOUNT_DENOMINATOR)`. Split amounts are based on undiscounted price. This means the minimum payment for a discounted tier with splits is driven by the full-price split amount, not the discounted NFT price.

### FF-003: setMetadata uses address(this) as tokenUriResolver sentinel
**Severity:** LOW (Informational)
**Source:** Category 1 (Purpose)
**File:** `JB721TiersHook.sol:423`

```solidity
if (tokenUriResolver != IJB721TokenUriResolver(address(this))) {
```
Uses `address(this)` as sentinel for "don't update." Unconventional — `address(0)` is the standard sentinel. If someone passes the hook's own address as a resolver, the update is silently skipped.

### FF-004: defaultReserveBeneficiaryOf globally overwritten by useReserveBeneficiaryAsDefault
**Severity:** LOW
**Source:** Category 2 (Ordering) + Category 5 (Boundaries)
**File:** `JB721TiersHookStore.sol:886-889`

Adding a tier with `useReserveBeneficiaryAsDefault = true` overwrites the default reserve beneficiary for ALL tiers that don't have a tier-specific one. This could redirect reserves for existing tiers.

### FF-005: Duplicate external calls in calculateSplitAmounts
**Severity:** LOW (Gas)
**Source:** Category 1 (Purpose)
**File:** `JB721TiersHookLib.sol:144,147`

`store.tierOf()` is called twice per iteration — once for `splitPercent`, once for `price`. Both could be fetched from a single call.

### FF-006: _sendPayoutToSplit silently drops funds when split has no beneficiary and no projectId
**Severity:** LOW
**Source:** Category 6 (Return/Error)
**File:** `JB721TiersHookLib.sol:255-283`

If `split.projectId == 0` AND `split.beneficiary == address(0)`, the function returns without sending. Funds are stuck. (Note: the splits contract should prevent this configuration, but the library doesn't guard against it.)

### FF-007: _addToBalance silently drops leftover when project has no terminal
**Severity:** LOW
**Source:** Category 6 (Return/Error)
**File:** `JB721TiersHookLib.sol:295-296`

After distributing to all splits, leftover funds are sent back to the project via `_addToBalance`. If the project has no terminal for the token, the function silently returns and funds are stuck.

---

## Pass 2 (State) — Raw Hypotheses

### SI-001: No coupled state inconsistency found in ERC721._balances ↔ STORE.tierBalanceOf
**Verdict:** SOUND

Both are updated atomically in `_update` → `recordTransferForTier`. All mint, burn, and transfer paths go through `_update`. No path modifies one without the other.

### SI-002: No coupled state inconsistency found in remainingSupply ↔ numberOfReservesMintedFor
**Verdict:** SOUND

`recordMint` decrements `remainingSupply` and checks `remainingSupply >= _numberOfPendingReservesFor`. `recordMintReservesFor` increments `numberOfReservesMintedFor` and decrements `remainingSupply`. The invariant `remainingSupply >= pendingReserves` is maintained by the check in `recordMint`.

### SI-003: No coupled state inconsistency found in payCreditsOf accounting
**Verdict:** SOUND

Credits are tracked per beneficiary. When payer == beneficiary, credits are combined with payment value. When payer != beneficiary, credits are preserved unchanged. The final credit value accurately reflects leftover + unused credits.

### SI-004: cashOutWeightOf uses full price (not discounted) — consistent with totalCashOutWeight
**Verdict:** SOUND (by design)

Both `cashOutWeightOf` and `totalCashOutWeight` use `_storedTierOf[hook][tierId].price` (the base price), not the discounted price. This is documented as intentional — discounts are transient and don't affect cash-out value.

### SI-005: totalCashOutWeight includes pending reserves — consistent with design
**Verdict:** SOUND (by design)

Pending reserves are included in `totalCashOutWeight` to prevent early cashers from extracting disproportionate value before reserves are minted.

---

## Pass 3 (Feynman re-interrogation on Pass 2 items)

No new suspects from Pass 2. All coupled state pairs verified as SOUND. No new findings.

---

## Pass 4 (State re-analysis)

No new coupled pairs or gaps from Pass 3. Convergence reached.

---

## Convergence: 4 passes (2 Feynman + 2 State). No new findings in Pass 3 or 4.
