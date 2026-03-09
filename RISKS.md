# nana-721-hook-v6 -- Risks

Deep implementation-level risk analysis covering all contracts in the 721 tiered hook system.

---

## Trust Assumptions

1. **Project Owner / Hook Owner** -- Can adjust tiers (add/remove), set metadata, set discount percent, manually mint from `allowOwnerMint` tiers, and configure hook flags. Full control over NFT economics within the boundaries enforced by immutable per-tier flags.
2. **Core Protocol (JBMultiTerminal)** -- The hook trusts that `afterPayRecordedWith()` and `afterCashOutRecordedWith()` are only called by a registered terminal. Verification at `JB721Hook.sol` lines 194-197 and 236-237 via `DIRECTORY.isTerminalOf()`.
3. **JBDirectory** -- Trusted to correctly report terminal registrations. If compromised, arbitrary addresses could call pay/cashout hooks.
4. **JBSplits** -- Trusted to store and return correct split configurations for tier split groups. The hook delegates split group management to this contract.
5. **Token URI Resolver** -- If set, controls all NFT metadata rendering. Cannot affect funds but can misrepresent NFT properties. Set via `SET_721_METADATA` permission.
6. **Store Contract** -- `JB721TiersHookStore` manages all tier state using a `msg.sender`-keyed trust model. The hook delegates pricing, supply, and reserve logic to the store.
7. **JBPrices** -- If a prices contract is configured (for cross-currency payments), the hook trusts it for price conversion. A reverting price feed will block all payments in non-native currencies.

---

## Risk Analysis

### R-1: Default Reserve Beneficiary Global Overwrite

- **Severity**: MEDIUM
- **Location**: `JB721TiersHookStore.sol` lines 890-897 (`recordAddTiers`)
- **Description**: When adding a tier with `useReserveBeneficiaryAsDefault = true`, the `defaultReserveBeneficiaryOf[msg.sender]` is overwritten. This silently redirects reserve mints for ALL existing tiers that rely on the default (i.e., tiers without a tier-specific `_reserveBeneficiaryOf` entry).
- **Attack scenario**: A project owner adds a new tier with `useReserveBeneficiaryAsDefault = true` and a different beneficiary address. Existing tiers whose reserves were flowing to the old default now silently redirect to the new address.
- **Tested**: YES -- `test/regression/L34_ReserveBeneficiaryOverwrite.t.sol` explicitly tests this behavior with 3 scenarios.
- **Mitigation**: Documented via `@dev WARNING` in the store. Callers should use per-tier beneficiaries (`useReserveBeneficiaryAsDefault = false`) when adding tiers to hooks with existing tiers.

### R-2: 100% Discount Enables Free Minting With Full Cash-Out Weight

- **Severity**: HIGH
- **Location**: `JB721TiersHookStore.sol` lines 1069-1071 (`recordMint`), `JB721Constants.sol` line 6
- **Description**: Setting `discountPercent = 200` (the `DISCOUNT_DENOMINATOR`) makes the effective mint price zero: `price - mulDiv(price, 200, 200) = 0`. However, the cash-out weight is always based on the original `storedTier.price` (lines 415-417 of `cashOutWeightOf`), not the discounted price. An attacker granted discount-setting permission could set 100% discount, mint for free, then cash out at full weight.
- **Attack scenario**: Compromised operator with `SET_721_DISCOUNT_PERCENT` permission sets discount to 200 on a high-value tier. Mints for free. Burns NFTs via cash-out to extract funds proportional to the original price.
- **Tested**: YES -- `test/721HookAttacks.t.sol` tests 2 and 3 cover discount behavior and `cannotIncreaseDiscountPercent` enforcement.
- **Mitigation**: Use `cannotIncreaseDiscountPercent = true` on tiers where this is a concern. Only grant `SET_721_DISCOUNT_PERCENT` to trusted addresses. The `discountPercent > storedTier.discountPercent && cannotIncreaseDiscountPercent` check at store line 1176 enforces the immutable cap.

### R-3: Tier Split Fund Distribution -- Reentrancy Surface

- **Severity**: MEDIUM
- **Location**: `JB721TiersHookLib.sol` lines 265-285 (`_distributeSingleSplit`) and lines 312-315 (`_sendPayoutToSplit`)
- **Description**: During `afterPayRecordedWith()`, if tiers have `splitPercent > 0`, the hook distributes forwarded funds to split beneficiaries. For native token splits, this involves a low-level `.call{value: amount}("")` to the beneficiary address (line 314). This is an external call to an untrusted address during payment processing.
- **Reentrancy path**: `afterPayRecordedWith` -> `_processPayment` -> `distributeAll` -> `_distributeSingleSplit` -> `_sendPayoutToSplit` -> `beneficiary.call{value}` -- the beneficiary could reenter the hook.
- **Why it is mitigated**: The NFT mint (`_mintAll`) happens BEFORE split distribution (line 646 vs. line 678 in `JB721TiersHook.sol`). The store's `recordMint` has already decremented supply. Pay credits are already updated. A reentrant call to `afterPayRecordedWith` would require terminal authorization and would process as a separate independent payment.
- **Tested**: PARTIALLY -- Split distribution is tested in `test/unit/tierSplitRouting_Unit.t.sol` and `test/regression/L36_SplitNoBeneficiary.t.sol`, but no explicit reentrancy test exists for the `.call{value}` path.
- **Mitigation**: State is settled before external calls. The terminal authorization check prevents casual reentrancy. No explicit `ReentrancyGuard` is used.

### R-4: Split Beneficiary With No Recipient -- Fund Routing

- **Severity**: LOW (fixed)
- **Location**: `JB721TiersHookLib.sol` lines 300-323 (`_sendPayoutToSplit`)
- **Description**: A split with `projectId == 0` and `beneficiary == address(0)` previously had undefined behavior. The current implementation returns `false`, causing the calling function to keep those funds in `leftoverAmount`, which is then routed to the project's balance via `_addToBalance` (line 282-284).
- **Tested**: YES -- `test/regression/L36_SplitNoBeneficiary.t.sol` verifies funds are routed to the project's balance.
- **Mitigation**: Fixed by design. Funds are never silently lost.

### R-5: Category Sort Order Enforcement -- Off-Chain Burden

- **Severity**: LOW
- **Location**: `JB721TiersHookStore.sol` lines 820-822 (`recordAddTiers`)
- **Description**: Tiers must be sorted by category when added. The store reverts `InvalidCategorySortOrder` if violated. This is an on-chain enforcement that protects invariants, but the error is difficult to debug for integrators.
- **Tested**: YES -- Implicit in all tier creation tests.
- **Mitigation**: Validate tier ordering off-chain before submitting transactions.

### R-6: Soft Removal Preserves Cash-Out Weight

- **Severity**: LOW (by design)
- **Location**: `JB721TiersHookStore.sol` lines 1139-1156 (`recordRemoveTierIds`), lines 460-478 (`totalCashOutWeight`)
- **Description**: Removing a tier only marks it in a bitmap (`_removedTiersBitmapWordOf`). The tier data (`_storedTierOf`) is not deleted. `totalCashOutWeight()` iterates by `maxTierIdOf` (line 462-466), not by the sorted tier list, so removed tiers' minted NFTs continue to contribute to cash-out weight. Existing NFTs from removed tiers retain their full cash-out value.
- **Attack scenario**: None -- this is intentional. Prevents retroactive value destruction of already-minted NFTs.
- **Tested**: YES -- `test/721HookAttacks.t.sol` test 5 explicitly verifies cash-out weight is preserved after tier removal.
- **Mitigation**: By design. Tier removal prevents new mints, not cash-outs.

### R-7: Pay Credit Accumulation -- Payer vs. Beneficiary Separation

- **Severity**: LOW
- **Location**: `JB721TiersHook.sol` lines 604-616 (`_processPayment`)
- **Description**: Pay credits are tracked per beneficiary, not per payer. When `payer != beneficiary`, the payer's existing credits are NOT applied to the mint. Credits from the payment's leftover are stored for the beneficiary. This means a payer who directs payment to another beneficiary loses access to any overspend -- it becomes the beneficiary's credit.
- **Tested**: PARTIALLY -- Pay credit tests exist in `test/unit/pay_Unit.t.sol` but the payer-beneficiary divergence case may not be exhaustively covered.
- **Mitigation**: This is documented behavior. Payers should be aware that credits accrue to the beneficiary.

### R-8: Reserve Supply Protection -- Post-Mint Check

- **Severity**: MEDIUM (fixed)
- **Location**: `JB721TiersHookStore.sol` lines 1079-1095 (`recordMint`)
- **Description**: The store decrements `remainingSupply` BEFORE checking whether enough supply remains for pending reserves (lines 1081-1086). After decrementing, it checks `remainingSupply < _numberOfPendingReservesFor(...)`. This is the correct order because `_numberOfPendingReservesFor` needs to see the post-mint state (the new non-reserve mint increases pending reserves). Without this ordering, the last available slot could be consumed by a paid mint, making pending reserves unmintable.
- **Tested**: YES -- `test/unit/M6_TierSupplyCheck.t.sol` provides 4 targeted tests for this edge case with varying supply and reserve frequency combinations.
- **Mitigation**: The decrement-then-check pattern is intentional and correct. The test proves a 7th paid mint correctly reverts when it would steal a reserve slot.

### R-9: Price Feed Dependency -- DoS Vector

- **Severity**: MEDIUM
- **Location**: `JB721TiersHookLib.sol` lines 121-138 (`normalizePaymentValue`)
- **Description**: When the hook's pricing currency differs from the payment currency and a `JBPrices` contract is configured, the hook calls `prices.pricePerUnitOf()` to normalize the payment value. If the price feed reverts (e.g., stale Chainlink data, sequencer down on L2), all payments in non-native currencies will revert. This is a DoS vector but not a fund-loss vector.
- **Tested**: NOT directly tested for the revert-on-stale-feed scenario.
- **Mitigation**: If `address(prices) == address(0)`, payments in non-matching currencies silently return `(0, false)` and the hook skips minting (line 600). Projects using cross-currency pricing should monitor feed health.

### R-10: Large Tier Array Gas Exhaustion

- **Severity**: LOW
- **Location**: `JB721TiersHookStore.sol` lines 253-333 (`tiersOf`), lines 358-380 (`votingUnitsOf`), lines 391-400 (`balanceOf`), lines 338-349 (`totalSupplyOf`), lines 460-478 (`totalCashOutWeight`)
- **Description**: Several view functions iterate from `maxTierIdOf` down to 1. With many tiers (up to 65,535 theoretically), these functions could exceed block gas limits. `totalCashOutWeight()` iterates ALL tier IDs (not just active ones), making it the most gas-intensive.
- **Attack scenario**: An attacker with `ADJUST_721_TIERS` permission adds thousands of tiers, causing `totalCashOutWeight()` to become uncallable. Since `beforeCashOutRecordedWith()` calls `totalCashOutWeight()` (line 115 of `JB721Hook.sol`), this could block all NFT cash-outs.
- **Tested**: `test/721HookAttacks.t.sol` test 10 tests `maxSupplyTier_noOverflow` but does not test gas limits with many tiers.
- **Mitigation**: The `maxTierIdOf` is capped at `type(uint16).max` (65,535) by the store (line 781-783). Keep tier count manageable in practice.

### R-11: Metadata Decode Failure -- Silent Skip

- **Severity**: LOW
- **Location**: `JB721TiersHook.sol` lines 622-648 (`_processPayment`)
- **Description**: If `JBMetadataResolver.getDataFor()` returns `found = false` (line 627), the hook skips NFT minting entirely. If `preventOverspending` is also false (the default), the payment goes through and the entire amount becomes pay credits for the beneficiary. No NFTs are minted, but the payment is not reverted.
- **Tested**: PARTIALLY -- `test/721HookAttacks.t.sol` test 6 tests invalid tier IDs with `preventOverspending = true`, but the silent-skip path (malformed metadata + `preventOverspending = false`) lacks a dedicated test.
- **Mitigation**: Use `JBMetadataResolver` for encoding. Set `preventOverspending = true` if unintended credit accumulation is a concern.

### R-12: ERC-721 Receiver Callback -- Potential DoS on Mint

- **Severity**: LOW
- **Location**: `ERC721.sol` lines 466-483 (`_checkOnERC721Received`), `JB721TiersHook.sol` line 579 (`_mint`)
- **Description**: The hook uses `_mint()` (not `_safeMint()`), so the `onERC721Received` callback is NOT triggered during minting. However, `safeTransferFrom` and `transferFrom` do trigger the `_update` override which calls `STORE.recordTransferForTier()` -- this is a cross-contract call during every transfer.
- **Tested**: Not specifically for DoS via receiver callbacks.
- **Mitigation**: `_mint()` avoids the receiver callback, preventing mint-time DoS. Transfers use the standard ERC-721 flow.

### R-13: Token URI Resolver -- Arbitrary External Call

- **Severity**: LOW
- **Location**: `JB721TiersHookLib.sol` lines 396-407 (`resolveTokenURI`), store line 551-556 (`_getTierFrom`)
- **Description**: If a `tokenUriResolver` is set, `tokenURI()` and `tiersOf(..., includeResolvedUri=true)` make external calls to the resolver contract. A malicious resolver could revert (blocking metadata reads) or return misleading data. Since these are view functions, there is no fund risk, but integrators (marketplaces, frontends) could be affected.
- **Tested**: NOT directly tested for malicious resolver behavior.
- **Mitigation**: Only the hook owner (via `SET_721_METADATA`) can set the resolver. The resolver cannot affect fund flows.

### R-14: Split Distribution -- Terminal Pay/AddToBalance External Calls

- **Severity**: MEDIUM
- **Location**: `JB721TiersHookLib.sol` lines 340-377 (`_terminalAddToBalance`, `_terminalPay`)
- **Description**: When distributing split funds to projects, the library calls `terminal.pay()` or `terminal.addToBalanceOf()` on the target project's primary terminal. These are external calls to potentially untrusted terminal contracts. For ERC-20 tokens, `SafeERC20.forceApprove()` is used before the call (lines 353, 373).
- **Reentrancy path**: The target terminal could call back into the hook during `pay()` processing. However, since the hook's own state (supply, credits) is already settled before distribution begins, reentrancy through this path cannot double-mint or corrupt state.
- **Tested**: `test/unit/tierSplitRouting_Unit.t.sol` tests split distribution with mocked terminals.
- **Mitigation**: State is fully settled before distribution. `SafeERC20` handles token approval safely.

### R-15: Initialize Front-Running on Deterministic Clones

- **Severity**: LOW
- **Location**: `JB721TiersHookDeployer.sol` lines 78-84 (`deployHookFor`)
- **Description**: When deploying with a salt (deterministic address via `LibClone.cloneDeterministic`), the salt is derived from `keccak256(abi.encode(_msgSender(), salt))`. An attacker who knows the deployer's address and salt could front-run the deployment. However, since `initialize()` is called in the same transaction as the clone creation (line 88-97), and ownership is transferred to `_msgSender()` (line 100), the front-runner would end up with a hook they do not own.
- **Tested**: NOT directly tested for front-running scenarios.
- **Mitigation**: The sender-specific salt derivation prevents third-party address prediction. The atomic deploy+initialize+transfer pattern prevents initialization hijacking.

### R-16: cleanTiers() -- Permissionless Tier List Reorganization

- **Severity**: LOW
- **Location**: `JB721TiersHookStore.sol` lines 726-763 (`cleanTiers`)
- **Description**: `cleanTiers()` is callable by anyone. It reorganizes the sorted tier linked list to skip removed tiers. While this is pure bookkeeping (no value at risk), a griefing attacker could call it repeatedly to waste gas or to ensure the tier list is in a particular order.
- **Tested**: NOT specifically tested for griefing.
- **Mitigation**: The function is idempotent and only modifies the `_tierIdAfter` mapping. No economic impact.

### R-17: Voting Units Manipulation via Tier Addition

- **Severity**: LOW
- **Location**: `JB721TiersHookStore.sol` lines 829-835 (`recordAddTiers`)
- **Description**: If `noNewTiersWithVotes` is NOT set, an owner can add new tiers with custom `votingUnits`. This could allow governance manipulation by creating tiers with high voting power relative to their price. If `useVotingUnits = false`, voting power defaults to the tier's price, which could also be set to artificially high values.
- **Tested**: PARTIALLY -- The flag enforcement is tested in the store invariant tests, but governance manipulation scenarios are not explicitly tested.
- **Mitigation**: Set `noNewTiersWithVotes = true` at initialization for projects where governance voting power is economically significant.

### R-18: mulDiv Rounding in Discount Application

- **Severity**: LOW
- **Location**: `JB721TiersHookStore.sol` line 1070 (`recordMint`)
- **Description**: The discounted price is calculated as `price - mulDiv(price, discountPercent, DISCOUNT_DENOMINATOR)`. The `mulDiv` from PRBMath rounds down, meaning the discount amount is slightly less than the mathematical result, and the effective price is slightly higher than expected. For small prices, this could mean the discount has no effect (e.g., `price=1, discountPercent=1` -> `mulDiv(1, 1, 200) = 0`).
- **Tested**: PARTIALLY -- Discount tests exist in `test/721HookAttacks.t.sol` tests 2-3, but edge cases with very small prices are not explicitly tested.
- **Mitigation**: Rounding always favors the protocol (charges slightly more). Economically insignificant for typical tier prices.

### R-19: Transfer Pause Bypass via Tier Configuration

- **Severity**: LOW
- **Location**: `JB721TiersHook.sol` lines 715-727 (`_update`)
- **Description**: Transfer pausing only applies to tiers with `transfersPausable = true` AND requires the current ruleset's metadata to have `transfersPaused` set (bit 0). If a tier is created with `transfersPausable = false`, its NFTs can never be paused regardless of ruleset settings. This is by design but could surprise project owners who expect blanket pause capability.
- **Tested**: PARTIALLY -- The transfer pause logic is tested but not for the interaction between tier-level and ruleset-level flags.
- **Mitigation**: Set `transfersPausable = true` on all tiers where pause capability is desired.

---

## MEV / Frontrunning Vectors

### F-1: Tier Addition Frontrunning

An attacker who sees a pending `adjustTiers()` transaction could front-run it with payments to mint NFTs from existing tiers before the new (possibly cheaper or more favorable) tiers are added. This is standard mempool visibility risk and not specific to this hook.

### F-2: Discount Change Frontrunning

When the owner calls `setDiscountPercentOf()` to increase a discount, a frontrunner could observe the pending transaction and mint before the discount takes effect (paying the higher price). Conversely, when decreasing a discount, a frontrunner could mint at the current lower price before the increase takes effect.

### F-3: Cash-Out Sandwich

An attacker could observe a large cash-out and front-run it with their own cash-out to claim a larger share of the surplus (since `totalCashOutWeight` decreases after each burn). This is a standard bonding curve risk inherited from the core protocol.

---

## Reentrancy Analysis

### External Call Map

1. **`afterPayRecordedWith()`** -> `_processPayment()`:
   - `STORE.recordMint()` (cross-contract, trusted)
   - `_mint()` (internal, no receiver callback)
   - `JB721TiersHookLib.distributeAll()` via DELEGATECALL:
     - `SPLITS.splitsOf()` (cross-contract, trusted)
     - `split.beneficiary.call{value}()` (untrusted external call)
     - `terminal.pay()` (cross-contract, semi-trusted)
     - `terminal.addToBalanceOf()` (cross-contract, semi-trusted)
     - `SafeERC20.safeTransfer()` (token transfer)
     - `SafeERC20.forceApprove()` (token approval)

2. **`afterCashOutRecordedWith()`**:
   - `_ownerOf()` (internal read)
   - `_burn()` -> `_update()` (internal) -> `STORE.recordTransferForTier()` (cross-contract, trusted)
   - `STORE.recordBurn()` (cross-contract, trusted)

3. **`adjustTiers()`**:
   - `JB721TiersHookLib.adjustTiersFor()` via DELEGATECALL:
     - `STORE.recordRemoveTierIds()` (cross-contract, trusted)
     - `STORE.recordAddTiers()` (cross-contract, trusted)
     - `SPLITS.setSplitGroupsOf()` (cross-contract, trusted)

4. **`mintFor()`**:
   - `STORE.recordMint()` (cross-contract, trusted)
   - `_mint()` (internal, no receiver callback)

5. **`mintPendingReservesFor()`**:
   - `RULESETS.currentOf()` (cross-contract, trusted)
   - `STORE.recordMintReservesFor()` (cross-contract, trusted)
   - `STORE.reserveBeneficiaryOf()` (cross-contract, trusted)
   - `_mint()` (internal, no receiver callback)

### Reentrancy Assessment

**No explicit reentrancy guard** (`ReentrancyGuard`) is used. Protection relies on state ordering:

- All `STORE.record*` calls (state mutations) happen BEFORE any untrusted external calls.
- `_mint()` uses the non-safe variant, avoiding `onERC721Received` callbacks.
- The only untrusted external calls (split beneficiary `.call{value}`, terminal `.pay()`, terminal `.addToBalanceOf()`) happen after all state is settled.
- A reentering call would need terminal authorization (`DIRECTORY.isTerminalOf`) and would be processed as an independent operation with its own state changes.

**Risk level**: LOW. The state-before-interaction pattern is consistently applied.

---

## Test Coverage Summary

### By Risk

| Risk | Has Direct Test | Invariant Covered | Fuzz Tested |
|------|:-:|:-:|:-:|
| R-1 Reserve beneficiary overwrite | YES (L34) | NO | NO |
| R-2 100% discount free mint | YES (attacks t2-t3) | NO | NO |
| R-3 Split distribution reentrancy | PARTIAL | NO | NO |
| R-4 Split no beneficiary | YES (L36) | NO | NO |
| R-5 Category sort order | YES (implicit) | NO | YES (handler) |
| R-6 Soft removal cash-out weight | YES (attacks t5) | YES (INV-721-2) | YES |
| R-7 Pay credit payer/beneficiary | PARTIAL | YES (INV-721-3) | YES |
| R-8 Reserve supply protection | YES (M6) | YES (INV-721-1,4) | YES |
| R-9 Price feed DoS | NO | NO | NO |
| R-10 Large tier array gas | PARTIAL | NO | NO |
| R-11 Metadata decode silent skip | PARTIAL | NO | NO |
| R-12 ERC-721 receiver DoS | NO | NO | NO |
| R-13 Token URI resolver abuse | NO | NO | NO |
| R-14 Terminal call reentrancy | PARTIAL (mocked) | NO | NO |
| R-15 Initialize front-running | NO | NO | NO |
| R-16 cleanTiers griefing | NO | NO | NO |
| R-17 Voting units manipulation | PARTIAL | NO | NO |
| R-18 mulDiv rounding | PARTIAL | NO | NO |
| R-19 Transfer pause bypass | PARTIAL | NO | NO |

### Test Suite Overview

| Category | File Count | What It Covers |
|----------|:----------:|----------------|
| Unit tests | 9 | `adjustTier`, `deployer`, `getters/constructor`, `mintFor/mintReservesFor`, `pay`, `redeem`, `tierSplitRouting`, `JBBitmap`, `JBIpfsDecoder` |
| Invariant tests | 2 + 2 handlers | `TierLifecycleInvariant` (6 invariants), `TieredHookStoreInvariant` (3 invariants) |
| Attack tests | 1 | 10 adversarial scenarios (zero price, max discount, reserves, supply, permissions, overflow) |
| Regression tests | 3 | L34 (reserve beneficiary overwrite), L35 (cached tier lookup), L36 (split no beneficiary) |
| E2E tests | 1 | Full lifecycle with deployer, payments, cash-outs |
| Fork tests | 1 | Deployment on live chain state |
| Metadata unit | 2 | `JB721TiersRulesetMetadataResolver`, `M6_TierSupplyCheck` |

### Notable Coverage Gaps

1. **No reentrancy test** for the split distribution `.call{value}` path.
2. **No price feed failure test** for cross-currency payment scenarios.
3. **No gas limit test** for operations with many tiers (hundreds+).
4. **No test** for token URI resolver returning malicious/reverting data.
5. **No test** for `initialize()` front-running on deterministic clones.
6. **No explicit fuzz test** for discount percent edge cases with very small prices.
7. **No cross-terminal reentry test** where a split's `terminal.pay()` triggers a callback into the hook.

---

## External Dependencies

| Dependency | What It Provides | Risk If Compromised |
|------------|-----------------|---------------------|
| `JBMultiTerminal` | Calls hook during pay/cashout | Arbitrary pay/cashout hook invocations |
| `JBDirectory` | Terminal registration lookups | Could allow unauthorized callers |
| `JBController` | Project lifecycle management | Hook deployment flow relies on it |
| `JBPermissions` | Permission checks for privileged functions | Could grant unauthorized access |
| `JBRulesets` | Current ruleset for pause checks | Could disable pause protections |
| `JBSplits` | Tier split group storage and retrieval | Could return incorrect splits |
| `JBPrices` | Cross-currency price conversion | Could return wrong prices or revert (DoS) |
| `JBOwnable` | Ownership model (EOA or project) | Ownership transfer mechanics |
| OpenZeppelin `ERC2771Context` | Meta-transaction support | Trusted forwarder could spoof `msg.sender` |
| PRBMath `mulDiv` | Fixed-point arithmetic | Rounding errors (bounded) |
| Solady `LibClone` | Minimal proxy cloning | Clone implementation bugs |
