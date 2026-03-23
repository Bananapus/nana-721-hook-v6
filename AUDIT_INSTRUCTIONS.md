# Audit Instructions -- nana-721-hook-v6

You are auditing the Juicebox V6 tiered NFT hook system. This hook allows Juicebox projects to sell tiered ERC-721 NFTs via payments and let holders cash out NFTs to reclaim funds. Your goal is to find bugs that lose funds, break invariants, or enable unauthorized access.

Read [ARCHITECTURE.md](./ARCHITECTURE.md) first for data flow context. Read [RISKS.md](./RISKS.md) for 19 known risks with test coverage mapping. Then come back here.

## Compiler and Version Info

| Setting | Value |
|---------|-------|
| Solidity version | 0.8.26 |
| EVM target | cancun |
| Optimizer | enabled, 200 runs |
| via-IR | not enabled |
| Fuzz runs | 4,096 |
| Invariant runs | 1,024 (depth 100) |

Source: [`foundry.toml`](./foundry.toml)

## Previous Audit Findings

A Nemesis automated audit was conducted on 2026-03-17. Results are in [`.audit/findings/nemesis-verified.md`](./.audit/findings/nemesis-verified.md). Summary:

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| NM-001 | MEDIUM | Unprotected external calls in tier split distribution cascade to full payment revert | **Remediated** -- hook callbacks, terminal calls, and native-token sends in `_sendPayoutToSplit` are now wrapped in try-catch; ERC-20 beneficiary `safeTransfer` remains unwrapped (reverts only if the token itself reverts) |
| NM-002 | LOW | `_addToBalance` silently drops funds when no primary terminal | Open |
| NM-003 | LOW | Missing `splitPercent` bounds validation in `recordAddTiers` | **Remediated** -- `SplitPercentExceedsBounds` check added at `JB721TiersHookStore.sol:866` |
| NM-004 | LOW | Implementation contract initializable | Open (no fund risk) |
| NM-005 | LOW | `setMetadata` uses non-standard sentinel for tokenUriResolver | Open (documented behavior) |

No prior formal audit with finding IDs from an external security firm has been conducted. See [RISKS.md](./RISKS.md) for the project's own risk assessment.

## Error Reference

| Error | Contract | Trigger Condition |
|-------|----------|-------------------|
| `JB721TiersHookStore_CantMintManually(uint256 tierId)` | JB721TiersHookStore | `recordMint` called with `isManualMint=true` on a tier with `allowOwnerMint=false` |
| `JB721TiersHookStore_CantRemoveTier(uint256 tierId)` | JB721TiersHookStore | `recordRemoveTierIds` called on a tier with `cannotBeRemoved=true` |
| `JB721TiersHookStore_DiscountPercentExceedsBounds(uint256 percent, uint256 limit)` | JB721TiersHookStore | `recordSetDiscountPercentOf` or `recordAddTiers` with `discountPercent > DISCOUNT_DENOMINATOR (200)` |
| `JB721TiersHookStore_DiscountPercentIncreaseNotAllowed(uint256 percent, uint256 storedPercent)` | JB721TiersHookStore | `recordSetDiscountPercentOf` increases discount on a tier with `cannotIncreaseDiscountPercent=true` |
| `JB721TiersHookStore_InsufficientPendingReserves(uint256 count, uint256 numberOfPendingReserves)` | JB721TiersHookStore | `recordMintReservesFor` called with `count > pendingReserves` |
| `JB721TiersHookStore_InsufficientSupplyRemaining(uint256 tierId)` | JB721TiersHookStore | `recordMint` when `remainingSupply < pendingReserves` after decrement |
| `JB721TiersHookStore_InvalidCategorySortOrder(uint256 tierCategory, uint256 previousTierCategory)` | JB721TiersHookStore | `recordAddTiers` with tiers not in ascending category order |
| `JB721TiersHookStore_InvalidQuantity(uint256 quantity, uint256 limit)` | JB721TiersHookStore | `recordAddTiers` with `initialSupply >= _ONE_BILLION` |
| `JB721TiersHookStore_ManualMintingNotAllowed(uint256 tierId)` | JB721TiersHookStore | `recordMint` called as manual mint when `noNewTiersWithOwnerMinting` flag is set and tier allows it |
| `JB721TiersHookStore_MaxTiersExceeded(uint256 numberOfTiers, uint256 limit)` | JB721TiersHookStore | `recordAddTiers` would push `maxTierIdOf` above `type(uint16).max` (65,535) |
| `JB721TiersHookStore_PriceExceedsAmount(uint256 price, uint256 leftoverAmount)` | JB721TiersHookStore | `recordMint` when tier's (discounted) price exceeds remaining payment amount |
| `JB721TiersHookStore_ReserveFrequencyNotAllowed(uint256 tierId)` | JB721TiersHookStore | `recordAddTiers` with `reserveFrequency > 0` when `noNewTiersWithReserves` flag is set |
| `JB721TiersHookStore_SplitPercentExceedsBounds(uint256 percent, uint256 limit)` | JB721TiersHookStore | `recordAddTiers` with `splitPercent` exceeding bounds |
| `JB721TiersHookStore_TierRemoved(uint256 tierId)` | JB721TiersHookStore | `recordMint` or `recordSetDiscountPercentOf` called on a removed tier |
| `JB721TiersHookStore_UnrecognizedTier(uint256 tierId)` | JB721TiersHookStore | Any operation referencing a `tierId` that does not exist (> `maxTierIdOf` or never created) |
| `JB721TiersHookStore_VotingUnitsNotAllowed(uint256 tierId)` | JB721TiersHookStore | `recordAddTiers` with `votingUnits > 0` when `noNewTiersWithVotes` flag is set |
| `JB721TiersHookStore_ZeroInitialSupply(uint256 tierId)` | JB721TiersHookStore | `recordAddTiers` with `initialSupply == 0` |
| `JB721TiersHook_AlreadyInitialized(uint256 projectId)` | JB721TiersHook | `initialize()` called on a hook that already has `PROJECT_ID != 0` |
| `JB721TiersHook_CurrencyMismatch(uint256 paymentCurrency, uint256 tierCurrency)` | JB721TiersHook | Payment currency differs from tier pricing currency and no price feed is configured |
| `JB721TiersHook_InvalidPricingDecimals(uint256 decimals)` | JB721TiersHook | `initialize()` with `pricingDecimals > 18` |
| `JB721TiersHook_MintReserveNftsPaused()` | JB721TiersHook | `mintPendingReservesFor` called when `mintPendingReservesPaused` ruleset flag is active |
| `JB721TiersHook_NoProjectId()` | JB721TiersHook | `initialize()` called with `projectId == 0` |
| `JB721TiersHook_Overspending(uint256 leftoverAmount)` | JB721TiersHook | Payment has leftover after minting and `allowOverspending` metadata flag is false |
| `JB721TiersHook_TierTransfersPaused()` | JB721TiersHook | NFT transfer attempted on a tier with `transfersPausable=true` when `transfersPaused` ruleset flag is active |
| `JB721Hook_InvalidCashOut()` | JB721Hook | `afterCashOutRecordedWith` called by a non-terminal address |
| `JB721Hook_InvalidPay()` | JB721Hook | `afterPayRecordedWith` called by a non-terminal address |
| `JB721Hook_UnauthorizedToken(uint256 tokenId, address holder)` | JB721Hook | `afterCashOutRecordedWith` with a token ID not owned by the cash-out holder |
| `JB721Hook_UnexpectedTokenCashedOut()` | JB721Hook | `beforeCashOutRecordedWith` called with `cashOutCount > 0` (fungible tokens cannot be cashed out through this hook) |

## Architecture

Four contracts, one library:

| Contract | Lines | Role |
|----------|------:|------|
| `JB721TiersHook` | ~790 | The hook itself. ERC-721 + data hook + pay hook + cash out hook. Handles payment processing, NFT minting, cash out burning, tier adjustment, reserve minting, discount setting, metadata, and split distribution. Delegates heavy logic to the library via DELEGATECALL. |
| `JB721TiersHookStore` | ~1230 | All tier state. Keyed by `msg.sender` (the hook address). Manages tier CRUD, supply tracking, reserve accounting, bitmap-based removal, sorted linked list, transfer balance tracking, voting units, discount enforcement. |
| `JB721TiersHookDeployer` | ~115 | Deploys hook clones (Solady `LibClone`). Optional deterministic addressing via salt. Atomic deploy + initialize + ownership transfer. Registers with `JBAddressRegistry`. |
| `JB721TiersHookProjectDeployer` | ~420 | Convenience: launches a project + hook in one transaction. Converts `JBPayDataHookRulesetConfig` to `JBRulesetConfig` with `useDataHookForPay: true` hardcoded. Also supports `launchRulesetsFor` and `queueRulesetsOf`. |
| `JB721TiersHookLib` (library) | ~634 | Extracted logic for EIP-170 compliance. Tier adjustments, split amount calculation, price normalization, weight adjustment, split fund distribution, token URI resolution. Called via DELEGATECALL from the hook. |

Supporting:
- `JB721Hook` (abstract, ~270 lines) -- Base ERC-721 with `beforePayRecordedWith`, `beforeCashOutRecordedWith`, `afterPayRecordedWith`, `afterCashOutRecordedWith`. Terminal authorization checks.
- `ERC721` (abstract) -- Minimal ERC-721 with initializable name/symbol.

## Key Flows

### Payment -> NFT Mint

```
Terminal.pay(metadata with tier IDs)
  -> beforePayRecordedWith()                     [JB721TiersHook, view]
     -> JB721TiersHookLib.calculateSplitAmounts() -- per-tier split amounts from tier prices
     -> JB721TiersHookLib.convertSplitAmounts()   -- currency conversion if pricing != payment currency
     -> JB721TiersHookLib.calculateWeight()        -- reduce weight by split fraction
     -> returns (weight, hookSpecifications[0] = {this, totalSplitAmount, splitMetadata})

  -- Terminal records payment in JBTerminalStore with adjusted weight --
  -- Terminal mints project tokens --

  -> afterPayRecordedWith(context)               [JB721TiersHook, payable]
     -> Terminal auth check (DIRECTORY.isTerminalOf)
     -> _processPayment(context)
        -> JB721TiersHookLib.normalizePaymentValue() -- convert to pricing currency
        -> Combine pay credits (only if payer == beneficiary)
        -> Decode metadata: (allowOverspending, tierIdsToMint)
        -> _mintAll(amount, tierIds, beneficiary)
           -> STORE.recordMint(amount, tierIds, false)
              -- For each tier: check removed, check supply, apply discount, check price, decrement supply, check reserves
           -> _mint(to, tokenId) for each  [no onERC721Received callback]
        -> Update pay credits
     -> JB721TiersHookLib.distributeAll(context.hookMetadata)  [if forwardedAmount > 0]
        -> Pull ERC-20 from terminal (safeTransferFrom)
        -> For each tier with splits: read splits from JBSplits, distribute via _sendPayoutToSplit
        -> Leftover -> _addToBalance (back to project)
```

### Cash Out -> NFT Burn

```
Terminal.cashOutTokensOf(metadata with token IDs)
  -> beforeCashOutRecordedWith()                 [JB721Hook, view]
     -> Decode token IDs from metadata
     -> cashOutCount = STORE.cashOutWeightOf(tokenIds)     -- sum of tier prices (original, not discounted)
     -> totalSupply = STORE.totalCashOutWeight()            -- all tiers, includes pending reserves
     -> returns (cashOutTaxRate, cashOutCount, totalSupply, hookSpecs)

  -- Terminal computes reclaim via bonding curve --

  -> afterCashOutRecordedWith(context)           [JB721Hook, payable]
     -> Terminal auth check
     -> For each token ID: verify owner == context.holder, _burn(tokenId)
     -> _didBurn(tokenIds) -> STORE.recordBurn(tokenIds)    -- increment burn counter
```

### Tier Management

```
Owner -> adjustTiers(tiersToAdd, tierIdsToRemove)
  -> Permission check: ADJUST_721_TIERS
  -> JB721TiersHookLib.adjustTiersFor() via DELEGATECALL
     -> STORE.recordRemoveTierIds(tierIdsToRemove)  -- bitmap mark, no data deletion
     -> STORE.recordAddTiers(tiersToAdd)             -- sorted insert into linked list
     -> SPLITS.setSplitGroupsOf() for tiers with splits configured
```

### Reserve Minting

```
Anyone -> mintPendingReservesFor(tierId, count)
  -> Check ruleset metadata: mintPendingReservesPaused (bit 1)
  -> STORE.recordMintReservesFor(tierId, count)
     -- Checks pendingReserves >= count
     -- Increments numberOfReservesMintedFor
     -- Decrements remainingSupply
  -> STORE.reserveBeneficiaryOf(hook, tierId) -- tier-specific or default
  -> _mint(to, tokenId) for each
```

## Storage Layout

### Tier Linked List (sorted by category)

Tiers are stored individually in `_storedTierOf[hook][tierId]` as `JBStored721Tier` structs. The sorted iteration order is maintained by:

- `_tierIdAfter[hook][tierId]` -- next tier in sorted order (0 means tierId+1 is next)
- `_tierIdAfter[hook][0]` -- first tier in sorted order
- `_lastTrackedSortedTierIdOf[hook]` -- last tier if explicitly tracked (else `maxTierIdOf`)
- `_startingTierIdOfCategory[hook][category]` -- first tier ID for a given category

New tiers are always assigned incrementing IDs (`maxTierIdOf + 1, +2, ...`) regardless of category. The linked list is updated to insert them at the correct sorted position.

### Tier Removal Bitmap

Tiers are never deleted from storage. Removal is tracked in `_removedTiersBitmapWordOf[hook]` using the `JBBitmap` library. Each word stores 256 tier removal flags. Removed tiers are skipped during sorted iteration but their data persists for:
- Cash out weight calculation (`totalCashOutWeight` iterates by maxTierIdOf, not by sorted list)
- Existing NFT metadata resolution
- Reserve minting (reserves can still be minted from removed tiers)

### Pay Credits

`payCreditsOf[beneficiary]` in the hook contract (not the store). Tracks overpayment in the pricing currency denomination. Only combined with incoming payment when `payer == beneficiary`.

### Token ID Encoding

`tokenId = tierId * 1_000_000_000 + tokenNumber`

Where `tokenNumber` is `initialSupply - remainingSupply` at mint time. This means:
- `tierIdOfToken(tokenId) = tokenId / 1_000_000_000`
- Max supply per tier: 999,999,999 (enforced as `_ONE_BILLION - 1`)
- Max tier ID: 65,535 (`type(uint16).max`)

### Split Group ID Encoding

Split groups are stored in `JBSplits` with a composite group ID:
```
groupId = uint256(uint160(hookAddress)) | (uint256(tierId) << 160)
```

## Key Constants

| Constant | Value | Where |
|----------|-------|-------|
| `DISCOUNT_DENOMINATOR` | 200 | `JB721Constants.sol` -- 200 = 100% discount, NOT 100 |
| `SPLITS_TOTAL_PERCENT` | 1,000,000,000 | `JBConstants` -- `splitPercent` is out of 1e9 |
| `_ONE_BILLION` | 1,000,000,000 | `JB721TiersHookStore` -- token ID namespace per tier |
| Max tier ID | 65,535 | `type(uint16).max` enforced in `recordAddTiers` |
| Max supply per tier | 999,999,999 | `_ONE_BILLION - 1` enforced in `recordAddTiers` |

## Gotchas -- Things That Trip Up Auditors

1. **Discount denominator is 200, not 100.** A `discountPercent` of 100 means 50% off. A `discountPercent` of 200 means 100% off (free). The formula: `effectivePrice = price - mulDiv(price, discountPercent, 200)`.

2. **Cash out weight uses original price, not discounted price.** `cashOutWeightOf` and `totalCashOutWeight` both use `storedTier.price` directly. If a tier has `discountPercent = 200` (free), NFTs minted for free still carry full cash-out weight. This is by design but creates an arbitrage vector if discount can be increased (see R-2 in RISKS.md).

3. **Category sort order is enforced on-chain.** `recordAddTiers` reverts with `InvalidCategorySortOrder` if tiers are not passed in ascending category order. This is a common integration footgun.

4. **Tier removal is soft.** `recordRemoveTierIds` only sets a bitmap flag. The stored tier data, cash-out weight, and reserve accounting all persist. `totalCashOutWeight` iterates by `maxTierIdOf`, not by the sorted list, so removed tier NFTs retain their cash-out value.

5. **Pay credits accrue to the beneficiary, not the payer.** When `payer != beneficiary`, the payer's existing credits are NOT applied to the mint. The leftover from the payment becomes the beneficiary's credit. This is documented but non-obvious.

6. **`splitPercent` is out of 1,000,000,000 (1e9), not 10,000.** A `splitPercent` of 500,000,000 means 50% of the tier's effective (discounted) price is routed to splits.

7. **`useReserveBeneficiaryAsDefault` overwrites the global default.** Adding a tier with this flag silently redirects reserve mints for ALL existing tiers that rely on the default beneficiary.

8. **No `ReentrancyGuard`.** The hook relies on state-before-interaction ordering and try-catch wrapping. All `STORE.record*` calls and `_mint()` calls happen before any untrusted external calls (split distribution). All external calls in `_sendPayoutToSplit` are wrapped in try-catch so a reverting recipient cannot block payments.

9. **`_mint()` is used, not `_safeMint()`.** The `onERC721Received` callback is NOT triggered during minting. This prevents mint-time DoS but means contracts that expect the callback won't detect incoming NFTs.

10. **`recordMint` decrements supply BEFORE checking reserves.** The remaining supply check `remainingSupply < _numberOfPendingReservesFor(...)` happens after the decrement. This is intentional -- the post-mint state correctly reflects the new non-reserve mint that may have created a new pending reserve.

11. **`totalCashOutWeight` includes pending reserves.** This dilutes cash-out value for existing holders by counting reserves that haven't been minted yet. By design -- prevents early cashers from extracting more than their fair share.

12. **`beforePayRecordedWith` computes split amounts in the pricing currency, then converts.** The split amount forwarded to the hook is in the payment token denomination. If the price feed has significant spread, the conversion can over/under-estimate.

## Priority Audit Areas

Audit in this order:

### 1. Split Distribution (Highest Risk)

The split distribution path in `JB721TiersHookLib.distributeAll()` is the largest attack surface:

- External calls to untrusted split hooks (`processSplitWith{value}`)
- External calls to arbitrary terminals (`terminal.pay()`, `terminal.addToBalanceOf()`)
- External calls to arbitrary beneficiary addresses (`.call{value}`)
- ERC-20 token transfers and approvals before external calls
- No `ReentrancyGuard` -- relies on state ordering and try-catch wrapping

All external calls in `_sendPayoutToSplit` are wrapped in try-catch so a single reverting recipient cannot brick all payments to the project. Behavior differs by token type:
- **Native token (ETH):** Split hooks, terminal calls, and beneficiary sends are wrapped in try-catch. On revert, ETH stays with the caller and the function returns `false`, routing the amount to the project's balance via `_addToBalance`.
- **ERC-20 split hooks:** Tokens are transferred via `safeTransfer` before the hook callback. The callback is wrapped in try-catch, but the function always returns `true` regardless of callback success — because the tokens have already left the contract, returning `false` would cause double-spend accounting in the leftover calculation.
- **ERC-20 terminal calls:** `forceApprove` is called before the terminal call. On failure, the approval is reset to zero to prevent dangling approvals, and the function returns `false`.

Verify that:
- State is fully settled before any external call in the distribution loop
- A reentering call through `terminal.pay()` cannot corrupt hook state
- `leftoverAmount` accounting is correct when `_sendPayoutToSplit` returns false
- ERC-20 `forceApprove` followed by external call cannot be exploited (approval not consumed -> leftover approval)
- The ERC-20 split hook path correctly returns `true` after `safeTransfer` regardless of callback outcome (prevents double-spend via leftover miscounting)

### 2. Discount / Cash Out Weight Interaction

The discount system creates a price asymmetry:
- Mint price: `price - mulDiv(price, discountPercent, 200)` (can be zero)
- Cash out weight: `price` (always original, never discounted)

Verify that:
- `cannotIncreaseDiscountPercent` is correctly enforced in `recordSetDiscountPercentOf`
- Split amounts use the discounted price (they do -- `calculateSplitAmounts` applies discount)
- There is no path to mint at discounted price and cash out at original weight without the owner explicitly enabling it

### 3. Reserve Accounting

Reserve mints interact with supply tracking:
- `_numberOfPendingReservesFor` uses `ceil(nonReserveMints / reserveFrequency) - reservesMinted`
- `recordMint` checks `remainingSupply < pendingReserves` after decrementing
- Reserve mints decrement `remainingSupply` and increment `numberOfReservesMintedFor`

Verify that:
- A paid mint cannot steal the last slot reserved for a pending reserve
- `_numberOfPendingReservesFor` never returns more than `remainingSupply`
- The rounding-up in pending reserve calculation is correct and consistent
- Changing `defaultReserveBeneficiaryOf` cannot create ghost reserves or destroy legitimate ones

### 4. Cross-Currency Price Normalization

Two conversion points:
- `normalizePaymentValue` -- converts payment amount to pricing currency for tier price comparison
- `convertSplitAmounts` -- converts split amounts from pricing currency to payment token denomination

Verify that:
- When `address(prices) == address(0)` and currencies differ, `normalizePaymentValue` returns `(0, false)` and the hook skips minting (no silent fund loss)
- A reverting price feed blocks payments but does not lose funds
- Rounding through the conversion chain (normalize -> split calc -> convert back) does not systematically favor the attacker
- The ratio used in `convertSplitAmounts` is the inverse of what `normalizePaymentValue` uses (it should be -- verify)

### 5. Initialization and Clone Security

`JB721TiersHookDeployer` creates minimal proxy clones:
- `initialize()` is guarded by `PROJECT_ID != 0` (not `Initializable`)
- Ownership is transferred to `_msgSender()` inside `initialize`, then to the deployer caller in `deployHookFor`

Verify that:
- The implementation contract (HOOK) cannot be initialized (its `PROJECT_ID` is 0 by default -- can someone call initialize on it?)
- Deterministic salt derivation (`keccak256(abi.encode(_msgSender(), salt))`) prevents cross-deployer address collision
- Front-running `deployHookFor` cannot hijack ownership

### 6. Linked List Integrity

Tier sorting is maintained by `_tierIdAfter` mappings:
- `recordAddTiers` inserts new tiers into the sorted list
- `cleanTiers` removes gaps from the sorted list
- `_nextSortedTierIdOf` defaults to `id + 1` when no explicit next is stored

Verify that:
- Adding tiers to an existing set preserves the correct sort order
- Removing and re-adding tiers does not corrupt the linked list
- `cleanTiers` (permissionless) cannot be used to manipulate tier ordering in a way that affects minting or pricing

## Invariants

These must hold. If you can break any, it's a finding:

1. **Supply cap**: For every tier, `initialSupply - remainingSupply` (minted count) never exceeds `initialSupply`.
2. **Reserve protection**: After any `recordMint`, `remainingSupply >= numberOfPendingReserves` for that tier.
3. **Token ID uniqueness**: No two distinct mints produce the same `tokenId` (guaranteed by `initialSupply - --remainingSupply` pattern).
4. **Cash out weight conservation**: `totalCashOutWeight` equals the sum of `price * (mintedCount + pendingReserves)` across all tiers.
5. **Balance tracking**: `sum(tierBalanceOf[hook][owner][tierId])` across all owners equals `initialSupply - remainingSupply - burned` for each tier.
6. **Credit conservation**: Pay credits increase by leftover after minting, decrease by amount used for minting. Never negative.
7. **Linked list completeness**: Iterating from `_firstSortedTierIdOf(hook, 0)` via `_nextSortedTierIdOf` visits every non-removed tier exactly once.
8. **Discount bound**: `discountPercent <= DISCOUNT_DENOMINATOR (200)` for every stored tier.
9. **Removal idempotency**: Removing an already-removed tier is a no-op (bitmap set is idempotent).
10. **NFT supply cap**: Minted count per tier never exceeds `initialSupply` (same as invariant 1, but auditors should verify the `_ONE_BILLION - 1` cap prevents token ID overflow into the next tier).

## Anti-Patterns to Hunt

| Pattern | Where to Look | Why It's Dangerous |
|---------|--------------|-------------------|
| DELEGATECALL from hook to library | `JB721TiersHook` → `JB721TiersHookLib` | Library executes in the hook's storage context. A subtle mismatch in storage layout assumptions could corrupt state. |
| `safeTransfer` before callback | `_sendPayoutToSplit` ERC-20 path | Tokens leave the contract before the hook callback. The function returns `true` regardless of callback success to prevent double-spend in leftover accounting. |
| `forceApprove` + external call | `_sendPayoutToSplit` terminal path | If the external call fails, the approval is reset to zero. But between `forceApprove` and the failure, the approval exists. Can an attacker exploit this window? |
| `mulDiv` rounding in price normalization | `normalizePaymentValue`, `convertSplitAmounts` | Rounding through the conversion chain (normalize → calculate splits → convert back) can compound. Verify rounding favors the protocol. |
| Bitmap-based removal with iteration by maxTierIdOf | `totalCashOutWeight`, `cleanTiers` | `totalCashOutWeight` iterates up to `maxTierIdOf`, not by sorted list. If many tiers are added and removed, gas cost grows unboundedly. |
| Clone initialization guard | `JB721TiersHookDeployer` | `initialize()` is guarded by `PROJECT_ID != 0`, not OpenZeppelin's `Initializable`. Verify the implementation contract cannot be initialized. |
| `_mint` instead of `_safeMint` | `JB721TiersHook` | No `onERC721Received` callback. Prevents mint-time DoS but contracts won't detect incoming NFTs. |
| Token ID overflow at tier boundary | `_generateTokenId` | `tokenId = tierId * 1_000_000_000 + tokenNumber`. If `tokenNumber` reaches `_ONE_BILLION`, it overflows into the next tier's namespace. Supply cap enforcement (`_ONE_BILLION - 1`) prevents this -- verify the enforcement is complete. |

## Testing Setup

```bash
cd nana-721-hook-v6
npm install
forge build
forge test

# Run with high verbosity
forge test -vvvv --match-test testExploitName

# Write a PoC
forge test --match-path test/audit/ExploitPoC.t.sol -vvv

# Run invariant tests
forge test --match-contract Invariant

# Gas analysis
forge test --gas-report
```

### Existing Test Coverage

| Category | Files | Coverage |
|----------|------:|---------|
| Unit tests | 13 | adjustTier, deployer, getters/constructor, mintFor/mintReservesFor, pay, redeem, tierSplitRouting, splitHookDistribution, JBBitmap, JBIpfsDecoder, pay_CrossCurrency, JB721TiersRulesetMetadataResolver, TierSupplyReserveCheck |
| Invariant tests | 2 + 2 handlers | TierLifecycleInvariant (6), TieredHookStoreInvariant (3) |
| Attack tests | 1 | 10 adversarial scenarios |
| Regression tests | 6 | BrokenTerminalDoesNotDos, CacheTierLookup, ProjectDeployerRulesets, ReserveBeneficiaryOverwrite, SplitDistributionBugs, SplitNoBeneficiary |
| E2E tests | 1 | Full lifecycle |
| Fork tests | 3 | ERC20CashOutFork, ERC20TierSplitFork, IssueTokensForSplitsFork |
| Supply edge cases | 1 | M6 -- 4 targeted tests |
| Reentrancy tests | 1 | TestSafeTransferReentrancy -- safeTransfer reentrancy scenarios |
| Voting units tests | 1 | TestVotingUnitsLifecycle -- voting power through mint/burn/transfer |

### Coverage Gaps

1. No gas limit test for operations with hundreds of tiers.
2. No test for malicious/reverting token URI resolver.
3. No test for `initialize()` front-running on deterministic clones.
4. No fuzz test for discount percent edge cases with very small prices.

## How to Report Findings

For each finding:

1. **Title** -- one line, starts with severity (CRITICAL/HIGH/MEDIUM/LOW)
2. **Affected contract(s)** -- exact file path and line numbers
3. **Description** -- what's wrong, in plain language
4. **Trigger sequence** -- step-by-step, minimal steps to reproduce
5. **Impact** -- what an attacker gains, what a user loses (with numbers if possible)
6. **Proof** -- code trace showing the exact execution path, or a Foundry test
7. **Fix** -- minimal code change that resolves the issue

**Severity guide:**
- **CRITICAL**: Direct fund loss, permanent DoS, or broken core invariant. Exploitable with no preconditions.
- **HIGH**: Conditional fund loss, privilege escalation, or broken invariant. Requires specific but realistic setup.
- **MEDIUM**: Value leakage, griefing with cost to attacker, incorrect accounting, degraded functionality.
- **LOW**: Informational, cosmetic, edge-case-only with no material impact.

**Before reporting -- verify it's not a false positive:**
- Is the "bug" already documented in [RISKS.md](./RISKS.md)?
- Does cash out weight using original price (not discounted) look intentional? (It is.)
- Does `totalCashOutWeight` including pending reserves look wrong? (It's by design.)
- Is `DISCOUNT_DENOMINATOR = 200` surprising but correct? (It is.)
- Does the store's `msg.sender`-keyed trust model handle the case? (The store trusts the hook.)
- Is the economic attack profitable after the core protocol's 2.5% fee on cash outs?

