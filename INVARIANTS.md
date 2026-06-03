# Invariants of `@bananapus/721-hook-v6`

Scope: the contracts shipped from this repo — `JB721TiersHook` (clone implementation), `JB721TiersHookStore` (shared accounting backend), `JB721TiersHookDeployer` and `JB721TiersHookProjectDeployer` (clone factories), `JB721Checkpoints` (lazy IVotes module) and its deployer, plus the libraries under `src/libraries/`. The hook is a per-clone Ownable (`JBOwnable`) data-hook for Juicebox V6 used by Croptop, Banny, Defifa, and general revnets to sell category-sorted tiered NFTs through the Juicebox pay / cash-out flow.

Companion docs: [ARCHITECTURE.md](./ARCHITECTURE.md), [RISKS.md](./RISKS.md), [USER_JOURNEYS.md](./USER_JOURNEYS.md), [ADMINISTRATION.md](./ADMINISTRATION.md), [AUDIT_INSTRUCTIONS.md](./AUDIT_INSTRUCTIONS.md), [SKILLS.md](./SKILLS.md), [CHANGELOG.md](./CHANGELOG.md).

The underlying terminal / controller / fee guarantees are inherited from `@bananapus/core-v6` and documented in `../INVARIANTS.md`. This file only describes what THIS repo's contracts add or constrain on top.

---

## Section A — Guarantees to paying users

## A.1 Paying-user mint

- **Tier price is fixed at tier creation.** `JBStored721Tier.price` is written once in `recordAddTiers` (`JB721TiersHookStore.sol:1020-1036`) and is never mutated afterward. The only price-shaped state that can change later is `discountPercent`, via `recordSetDiscountPercentOf` (`JB721TiersHookStore.sol:1375-1403`).
- **Discount can only go down once it is locked.** If a tier was created with `flags.cantIncreaseDiscountPercent = true`, `recordSetDiscountPercentOf` reverts with `JB721TiersHookStore_DiscountPercentIncreaseNotAllowed` whenever the new percent exceeds the stored percent (`JB721TiersHookStore.sol:1394-1398`). Without that flag, the project's discount operator can move discount in either direction up to `JB721Constants.DISCOUNT_DENOMINATOR` (200 = 100% off).
- **Discount denominator is 200, not 10,000.** A `discountPercent` of 100 means a 50% off mint, 200 means free. Integrators are responsible for displaying this correctly (`JB721Constants.sol:7`, accepted behavior 8.2 in RISKS).
- **Discounted mints retain full cash-out weight.** `cashOutWeightOf` reads `storedTier.price` directly without applying the discount (`JB721TiersHookStore.sol:478-491`). A holder who minted at a discount receives the same treasury share as a holder who paid full price. See RISKS §8.8.
- **Payer ≠ beneficiary → payer's credits are not applied.** `prepareMint` adds the existing credit balance to `leftoverAmount` only when `payer == beneficiary` (`JB721TiersHookLib.sol:236-240`). If a third party pays for someone else, only the fresh ETH counts; the beneficiary's credits remain untouched.
- **`cantBuyWithCredits` is enforced per tier.** `recordMint` accumulates `restrictedCost` over every iterated tier whose `cantBuyWithCredits` flag is set (`JB721TiersHookStore.sol:1259`). `prepareMint` then requires `restrictedCost <= value` (the fresh payment), reverting with `JB721TiersHook_CantBuyWithCredits` if credits would be needed to cover a restricted tier (`JB721TiersHookLib.sol:253-255`).
- **`remainingSupply ≥ pendingReserves` after every mint.** After decrementing `remainingSupply`, `recordMint` re-checks `_numberOfPendingReservesFor` and reverts with `JB721TiersHookStore_InsufficientSupplyRemaining` if the post-mint state would leave fewer slots than the pending reserve count requires (`JB721TiersHookStore.sol:1277-1283`). This is the same check that prevents paid mints from cannibalizing committed reserves.
- **Overspending is gated.** When the hook's `preventOverspending` flag is on, any payment whose `leftoverAmount > 0` after minting reverts with `JB721TiersHook_Overspending` (`JB721TiersHookLib.sol:259-261`). Payers can also opt-in to the same check via the metadata flag `payerAllowsOverspending = false` (`JB721TiersHookLib.sol:224-228`).
- **Unsupported currency → payment lands at project, no NFT mints.** When the terminal accounting context's currency differs from the hook's pricing currency and `PRICES == address(0)`, `JB721TiersHookLib.normalizePaymentValue` returns `valid = false` and `_processPayment` returns early without minting, crediting, or forwarding splits (`JB721TiersHook.sol:690-700`). Funds remain in the project's balance. This is intentional; see RISKS §8.3.
- **Sucker beneficiary substitution is authenticated by metadata.** Payments that go through a sucker on behalf of a remote user embed the real beneficiary under `JB721Constants.BENEFICIARY_METADATA_ID`; the hook decodes it from `context.hookMetadata` so NFTs mint to the original payer rather than the sucker contract (`JB721TiersHook.sol:702-711`).

## A.2 Holders — transfer, cash-out, voting

- **Cash-out weight uses the ORIGINAL tier price.** Both `cashOutWeightOf` (`JB721TiersHookStore.sol:495`) and the `totalCashOutWeightOf` running aggregate (accumulated from `storedTier.price` in `recordMint`/`recordBurn`, `:1276, :1152`) use the FULL tier price. Discounts never devalue an existing NFT.
- **Pending reserves are part of the cash-out denominator.** On each paid mint, `recordMint` adds the tier's full price for both the new outstanding NFT and any newly-accrued pending reserve to `totalCashOutWeightOf` (`JB721TiersHookStore.sol:1276`). This is intentional — it prevents reserve front-running, but means early cashers do not extract more than their diluted fair share. See RISKS §8.1 and §8.9.
- **Transfer pause requires BOTH the per-tier flag AND the ruleset flag.** `_update` short-circuits when `transfersPausable == false` on the tier (`JB721TiersHook.sol:769`); only if the tier is pausable does it then read `JB721TiersRulesetMetadataResolver.transfersPaused` on the current ruleset to decide whether to revert with `JB721TiersHook_TierTransfersPaused` (`JB721TiersHook.sol:775-783`). Burns to `address(0)` bypass the pause check.
- **First-owner is recorded on first transfer-out.** `_firstOwnerOf[tokenId]` is written exactly once, when an NFT first leaves its minter, so provenance survives later transfers (`JB721TiersHook.sol:786-787`).
- **`tierBalanceOf` stays in lockstep with ERC-721 balances.** `recordTransferForTier` decrements `from` and increments `to` for the token's tier on every `_update` (`JB721TiersHookStore.sol:1425-1439`).
- **Cash-out hook rejects mixed fungible+NFT cash-outs.** `beforeCashOutRecordedWith` reverts with `JB721Hook_UnexpectedTokenCashedOut` if `context.cashOutCount > 0` (`abstract/JB721Hook.sol:97-100`). Holders can only cash NFTs through this hook, not project tokens alongside them.
- **Lazy checkpoint deployment hazard.** `checkpoints` is `address(0)` after `initialize`. The first transfer (mint, send, or burn) triggers `CHECKPOINTS_DEPLOYER.deploy(address(this))` which CREATE2-clones `JB721Checkpoints` (`JB721TiersHook.sol:794-796`). **The first transferer pays the deployment cost (~1M gas).** This is a known hazard; integrators that mint a large batch and immediately transfer should price the gas for the first transfer accordingly. The deployer authenticates `msg.sender == hook` (`JB721CheckpointsDeployer.sol:52-54`), and `initialize` is one-shot (`JB721Checkpoints.sol:114-118`).
- **Voting power follows tier configuration.** Each tier contributes `balance × (useVotingUnits ? customVotingUnits : storedTier.price)` (`JB721TiersHookStore.sol:380-383, 436-440`). The checkpoint module reads tier voting units from the store on every transfer (`JB721Checkpoints.sol:128-129`).
- **`getPastTierVotingUnits` is the per-tier analogue of `getPastTotalSupply`.** `JB721Checkpoints` maintains a checkpointed per-tier eligible-voting-units trace (`_tierEligibleUnitsOf`) that distributors read as the exact historical denominator for tier-scoped reward pots (`JB721Checkpoints.sol:160-171`). It moves ONLY when a token's eligibility changes: it increments by the token's tier voting units when the token first gains an owner checkpoint — enrollment via `delegate(address, uint256[])` (`JB721Checkpoints.sol:95-103`) or the `from != address(0)` first-transfer branch of `onTransfer` (`JB721Checkpoints.sol:145-147`) — and decrements on burn (`JB721Checkpoints.sol:140-144`). **Mints write nothing** (the `from == address(0)` path is skipped, `JB721Checkpoints.sol:131-133`), so the mint path adds zero checkpoint gas and the trace tracks exactly the set of tokens `ownerOfAt` reports as eligible.

## A.3 Protections against external interference

- **Third-party EOA cannot:** mint NFTs to themselves, raise a tier's discount when `cantIncreaseDiscountPercent` is set, edit metadata, adjust tiers, change the default reserve beneficiary, drain forwarded split funds, redirect already-pending reserves to a new beneficiary (only future-pending reserves follow a beneficiary change — see RISKS §8.7), or re-route a transfer that the per-tier flag + ruleset flag combination has paused.
- **Hook authenticates all terminal callbacks.** `afterPayRecordedWith` and `afterCashOutRecordedWith` both check `DIRECTORY.isTerminalOf(projectId, msg.sender)` and `context.projectId == projectId` (`abstract/JB721Hook.sol:202-209, 251-258`). A rogue caller cannot ride either entrypoint.
- **ETH-attached calls must match the forwarded amount.** `afterPayRecordedWith` reverts with `JB721Hook_InvalidPayValue` if `msg.value != (token == NATIVE_TOKEN ? forwardedAmount : 0)` (`abstract/JB721Hook.sol:262-269`). Native-token mismatches and ERC-20-with-ETH-attached cannot pass.
- **Reentrancy posture.** No `ReentrancyGuard`. Safety relies on (a) terminal auth on every callback, (b) store updates happening before external mint/burn / split callbacks, (c) the project-side `_acceptingToken` transient guard in `JBMultiTerminal`. Split callbacks remain an arbitrary-code surface — RISKS §3.

## A.4 Permissionless reserve mint

- **`mintPendingReservesFor(tierId, count)` is permissionless** (`JB721TiersHook.sol:518-550`). Anyone can settle pending reserves; they are always minted to `reserveBeneficiaryOf(hook, tierId)` (per-tier override or hook default). The caller cannot redirect the recipient.
- The current ruleset must not have `mintPendingReservesPaused` set in its 721-specific metadata flags (`JB721TiersHook.sol:523-526`).

---

## Section B — Guarantees to the operator (project owner / delegates)

## B.1 Operator powers (project owner OR a `JBPermissions` delegate)

- **`adjustTiers(tiersToAdd, tierIdsToRemove)`** — `ADJUST_721_TIERS` (`JB721TiersHook.sol:351-365`). Append-only tier IDs; removed tiers stop accepting new paid/owner mints but existing NFTs remain valid and pending reserves stay mintable. New tiers must respect hook-wide flags (`noNewTiersWithVotes`, `noNewTiersWithReserves`, `noNewTiersWithOwnerMinting`) and category sort order (ascending). Category mis-sort reverts with `JB721TiersHookStore_InvalidCategorySortOrder` (`JB721TiersHookStore.sol:954-961`).
- **`mintFor(tierIds, beneficiary)`** — `MINT_721` (`JB721TiersHook.sol:373-392`). Forces a mint without payment; only succeeds on tiers whose `allowOwnerMint == true` (`JB721TiersHookStore.sol:1239-1240`). Bypasses `cantBuyWithCredits` and price entirely (the recorded mint passes `amount = type(uint256).max`).
- **`setDiscountPercentOf(tierId, discountPercent)` and `setDiscountPercentsOf(configs[])`** — `SET_721_DISCOUNT_PERCENT` (`JB721TiersHook.sol:417-444`). Subject to `cantIncreaseDiscountPercent` and the global discount denominator cap.
- **`setMetadata(name, symbol, baseUri, contractUri, tokenUriResolver, encodedIpfsUriTierId, encodedIpfsUri)`** — `SET_721_METADATA` (`JB721TiersHook.sol:458-508`). Empty strings / `IJB721TokenUriResolver(address(this))` sentinel = "leave unchanged". The resolver address `address(0)` is a valid clear, hence the `address(this)` sentinel. Future tier URIs can be pre-set under this permission (RISKS §8.10).
- **Project NFT owner alone**: `JBOwnable`'s `transferOwnership` / `transferOwnershipToProject` (inherited from `@bananapus/ownable-v6`).

## B.2 Operator powers the operator does NOT have

- **Cannot mutate price, supply, reserveFrequency, category, votingUnits, splitPercent, or any per-tier `cantBeRemoved` / `cantIncreaseDiscountPercent` / `cantBuyWithCredits` flag on an existing tier.** These are written once in `recordAddTiers` and never re-exposed for update.
- **Cannot bypass `cantBeRemoved`.** `recordRemoveTierIds` reverts with `JB721TiersHookStore_CantRemoveTier` (`JB721TiersHookStore.sol:1356-1359`).
- **Cannot retroactively cancel cash-out weight or reserve obligations** by removing a tier (RISKS §8.9).
- **Cannot raise a discount past `cantIncreaseDiscountPercent`** once it is set.
- **Cannot move pending reserves that are already owed to a specific beneficiary.** Pending reserves under the hook's default beneficiary DO follow the default if the default is changed (RISKS §8.7). Per-tier `_reserveBeneficiaryOf` overrides are permanent: there is no write path that updates `_reserveBeneficiaryOf[hook][tierId]` after the tier is created.
- **Cannot drain forwarded split funds** — `distributeAll` only routes per the on-chain split set; failures fall back to project balance via `addToBalanceOf`. RISKS §8.5 documents the residual stranding risk when BOTH paths fail.

## B.3 Hook-wide flags (set once at `initialize`)

`JB721TiersHookFlags` (`structs/JB721TiersHookFlags.sol:14-20`), stored via `recordFlags` (`JB721TiersHookStore.sol:1184-1186`):

- `noNewTiersWithReserves` — block future `reserveFrequency != 0` tiers.
- `noNewTiersWithVotes` — block future tiers with non-zero `votingUnits` or non-zero price (because price doubles as voting units when `useVotingUnits == false`).
- `noNewTiersWithOwnerMinting` — block future `allowOwnerMint = true` tiers.
- `preventOverspending` — leftover after mint reverts.
- `issueTokensForSplits` — when true, the portion of a payment that flows to tier splits still mints project tokens for the payer; when false (default), `weight` is reduced proportionally and split-bound funds do not mint project tokens.

These five flags are written once at clone init and never updated — `recordFlags` overwrites blindly, but is only called from `initialize` (`JB721TiersHook.sol:307-310`).

---

## Section C — Per-contract operation inventory

## C.1 `JB721TiersHook` — `src/JB721TiersHook.sol`

Clone-deployed per project. `JBOwnable`, `ERC2771Context`, `JB721Hook` (which inherits `ERC721`). Owner is the project NFT holder once `transferOwnershipToProject` runs.

**Initialization:**

- `initialize(initialProjectId, name, symbol, baseUri, tokenUriResolver, contractUri, tiersConfig, flags)` — public, one-shot (`JB721TiersHook.sol:247-314`). Guarded by `_initialized`. Implementation contract is pre-initialized in its constructor (line 146). Reverts `JB721TiersHook_AlreadyInitialized` on second call and `JB721TiersHook_NoProjectId` if zero is passed. Caller becomes initial owner.

**Terminal-driven (permissionless externally, authenticated internally):**

- `beforePayRecordedWith(context) view → (weight, hookSpecs)` (`JB721TiersHook.sol:194-223`). Called by the terminal during `pay`. Computes the adjusted `weight` (reduced for split portion unless `issueTokensForSplits`), the total split amount to forward to this hook, and packs `(beneficiary, payer, splitMetadata, splitCreditWeight)` into the pay-hook spec metadata.
- `afterPayRecordedWith(context) payable` (inherited `JB721Hook.sol:246-273`). Terminal-only. Validates msg.value ↔ forwardedAmount.token, then calls `_processPayment` which normalizes the value, decodes (beneficiary, payer, splitData), mints NFTs from the metadata-specified tiers, updates credits, and runs `distributeAll` on the forwarded split amount (`JB721TiersHook.sol:688-735`).
- `beforeCashOutRecordedWith(context) view → (taxRate, cashOutCount, totalSupply, surplus, hookSpecs)` (`abstract/JB721Hook.sol:84-127`). Reverts `JB721Hook_UnexpectedTokenCashedOut` if fungible tokens are also being cashed out. Decodes the tokenId list from metadata, sets `cashOutCount = cashOutWeightOf(tokenIds)` and `totalSupply = totalCashOutWeight()`.
- `afterCashOutRecordedWith(context) payable` (`abstract/JB721Hook.sol:191-240`). Terminal-only, must arrive with `msg.value == 0`. Burns each tokenId after verifying `_ownerOf(tokenId) == context.holder`; calls `_didBurn` (`JB721TiersHook.sol:586-589`) which increments `numberOfBurnedFor` per tier in the store.

**Project-NFT-owner / permissioned operator:**

- `adjustTiers(tiersToAdd, tierIdsToRemove)` — `ADJUST_721_TIERS` (line 351).
- `mintFor(tierIds, beneficiary) → tokenIds[]` — `MINT_721` (line 373).
- `setDiscountPercentOf(tierId, discountPercent)` — `SET_721_DISCOUNT_PERCENT` (line 417).
- `setDiscountPercentsOf(configs[])` — `SET_721_DISCOUNT_PERCENT` (line 428).
- `setMetadata(...)` — `SET_721_METADATA` (line 458).
- `transferOwnership(newOwner)` / `transferOwnershipToProject(projectId)` (inherited from `JBOwnable`).

**Permissionless:**

- `mintPendingReservesFor(tierId, count)` (line 518) and the batch form `mintPendingReservesFor(configs[])` (line 397). Recipient is the configured beneficiary, not the caller.

**View:**

- `firstOwnerOf(tokenId)`, `pricingContext()`, `balanceOf(owner)`, `cashOutWeightOf(tokenIds)`, `totalCashOutWeight()`, `tokenURI(tokenId)`, `hasMintPermissionFor(...)` returns `false` (so `JBController.mintTokensOf` never trusts this hook as a mint-permission grantor; `abstract/JB721Hook.sol:150-152`), `supportsInterface(id)`.

**Invariants maintained:**

- `_initialized` is monotonic true.
- `_packedPricingContext` is set once (line 281) and never written again.
- `pricingContext().decimals <= 18` (line 272).
- `_firstOwnerOf[tokenId]` is set at most once (line 787).
- Owner-only mutators all route through `_requirePermissionFrom({account: owner(), ...})` so a delegate's authority is scoped to the current project owner.

## C.2 `JB721TiersHookStore` — `src/JB721TiersHookStore.sol`

Shared singleton. Every mutating function is keyed by `msg.sender` and trusts it implicitly — a hook can only corrupt its own namespace.

**Reads (anyone):**

- `tierOfTokenId`, `tierOf`, `tiersOf(categories, includeUri, startingId, size)`, `tierPricingOf`, `tierTransferInfoOfTokenId`, `tierIdOfToken` (pure), `tierBalanceOf`, `balanceOf`, `totalSupplyOf`, `cashOutWeightOf`, `totalCashOutWeightOf`, `numberOfPendingReservesFor`, `numberOfReservesMintedFor`, `numberOfBurnedFor`, `isTierRemoved`, `flagsOf`, `maxTierIdOf`, `reserveBeneficiaryOf`, `defaultReserveBeneficiaryOf`, `encodedIpfsUriOf`, `encodedTierIPFSUriOf`, `tokenUriResolverOf`, `tierVotingUnitsOf`, `votingUnitsOf`.

**Writes (msg.sender treated as the hook):**

- `recordAddTiers(tiersToAdd) → tierIds[]` (line 909). Enforces: `maxTierIdOf + len ≤ uint16.max`, ascending category, `initialSupply ∈ [1, 1e9-1]` (zero supply reverts), no `initialSupply == 1 && reserveFrequency > 0` deadlock, `discountPercent ≤ DISCOUNT_DENOMINATOR`, `splitPercent ≤ SPLITS_TOTAL_PERCENT`, reserveFrequency-requires-beneficiary, hook-wide flag gates. Persists per-tier reserve beneficiary; if any tier sets `useReserveBeneficiaryAsDefault`, the hook's default is overwritten — affecting ALL existing tiers without a tier-specific beneficiary (line 1055-1062, see RISKS §1).
- `recordRemoveTierIds(tierIds)` (line 1341). Reverts `JB721TiersHookStore_CantRemoveTier` if `cantBeRemoved`, or `JB721TiersHookStore_UnrecognizedTier` if `tierId == 0 || > maxTierIdOf` (no removing future tiers).
- `recordMint(amount, tierIds, isOwnerMint) → (tokenIds, leftover, restrictedCost)` (line 1200). Enforces: tier not removed, `allowOwnerMint` for owner mints, supply remaining, price ≤ leftover, post-mint remaining supply ≥ pending reserves. Accumulates `restrictedCost` for tiers with `cantBuyWithCredits`.
- `recordMintReservesFor(tierId, count) → tokenIds[]` (line 1297). Reverts `JB721TiersHookStore_InsufficientPendingReserves` if `count > pending`.
- `recordBurn(tokenIds)` (line 1163). Increments `numberOfBurnedFor[hook][tierId]` per token; trusts the caller already burned them.
- `recordSetDiscountPercentOf(tierId, discountPercent)` (line 1375). Enforces tier not removed, `≤ DISCOUNT_DENOMINATOR`, and `cantIncreaseDiscountPercent` monotonicity.
- `recordSetEncodedIpfsUriOf(tierId, encodedIpfsUri)` (line 1409). No bounds; metadata permission gated upstream.
- `recordSetTokenUriResolver(resolver)` (line 1415). Plain write; `address(0)` clears.
- `recordTransferForTier(tierId, from, to)` (line 1425). Mint = from zero, burn = to zero, transfer = both.
- `recordFlags(flags)` (line 1184). Hook-wide flags blob; only called from `initialize`.
- `recordAccountingContextOf` — not part of this store (lives in core terminal store).
- `cleanTiers(hook)` — **permissionless** (line 832). Walks the sorted linked list, compacts out removed tiers, and updates `_lastTrackedSortedTierIdOf` so view functions stop traversing a removed trailing suffix.

**Invariants maintained per hook:**

- `maxTierIdOf` is monotonically non-decreasing and bounded by `uint16.max`.
- `_storedTierOf[hook][tierId].price`, `.initialSupply`, `.reserveFrequency`, `.splitPercent`, `.category`, `.packedBools` are write-once.
- `remainingSupply ≤ initialSupply` always; `remainingSupply ≥ numberOfPendingReservesFor` always after `recordMint` succeeds.
- `numberOfReservesMintedFor[hook][tierId] ≤ ceil(numberOfNonReserveMints / reserveFrequency)`.
- `numberOfBurnedFor + (initialSupply − remainingSupply) ≤ initialSupply`; circulating supply per tier = `initialSupply − remainingSupply − numberOfBurnedFor`.
- Category sort: each `_storedTierOf[hook][tierId].category ≥ _storedTierOf[hook][prev].category` along the linked list.
- Removed tiers stay removed: `_removedTiersBitmapWordOf` is set-only via `recordRemoveTierIds`; there is no un-remove path.
- Token IDs are deterministic: `tokenId = tierId * 1e9 + tokenNumber` where `tokenNumber = initialSupply − remainingSupply (post-decrement)`. Unique per `(hook, tierId)`.

## C.3 `JB721TiersHookProjectDeployer` — `src/JB721TiersHookProjectDeployer.sol`

ERC2771Context + JBPermissioned. Stateless except for `DIRECTORY` and `HOOK_DEPLOYER` immutables.

- `launchProjectFor(owner, deployTiersHookConfig, launchProjectConfig, controller, salt) payable → (projectId, hook)` (line 81). **Permissionless.** Reserves project ID via `JBProjects.createFor{value: msg.value}` (so the deployer forwards any creation fee), clones the hook, launches the project rulesets with `useDataHookForPay = true`, transfers hook ownership to the project, and transfers the project NFT to `owner`.
- `launchRulesetsFor(projectId, deployTiersHookConfig, launchRulesetsConfig, projectUri, controller, salt) → (rulesetId, hook)` (line 127). Requires `LAUNCH_RULESETS` AND `SET_TERMINALS` on the project owner; also `SET_PROJECT_URI` if `projectUri` non-empty. Deploys hook, transfers hook ownership to the project, then launches rulesets.
- `queueRulesetsOf(projectId, deployTiersHookConfig, queueRulesetsConfig, controller, salt) → (rulesetId, hook)` (line 187). Requires `QUEUE_RULESETS` on the project owner. Deploys hook, transfers hook ownership to project, then queues rulesets.
- `onERC721Received(operator, from, tokenId, data) view → selector` (line 226). Accepts the project NFT only when `msg.sender == DIRECTORY.PROJECTS() && from == address(0)` (i.e. it was just minted).

**Salt handling:** if `salt == bytes32(0)`, the underlying clone is non-deterministic. Otherwise the deployer rebinds the salt to `keccak256(abi.encode(_msgSender(), salt))` so two callers using the same external salt land at different addresses (`JB721TiersHookProjectDeployer.sol:101, 162, 209`).

## C.4 `JB721TiersHookDeployer` — `src/JB721TiersHookDeployer.sol`

- `deployHookFor(projectId, deployTiersHookConfig, salt) → newHook` (line 71). **Permissionless.** Clones via `LibClone.clone` or `LibClone.cloneDeterministic`, calls `initialize` on the clone with the caller as effective owner (via `_msgSender()` and the implicit `_transferOwnership` inside `initialize`), then `transferOwnership(_msgSender())`. Registers the clone in `IJBAddressRegistry` so the address can be verified across chains.

The hook's project association is bound at `initialize`; once set, it cannot change. The deployer is the only intended path to initialize a clone (anyone else calling `initialize` directly on a fresh clone would assign themselves ownership of the project's hook — but `JB721TiersHookProjectDeployer.launchProjectFor` is the canonical race-safe path: it reserves `projectId` before deploying the hook).

## C.5 `JB721Checkpoints` and `JB721CheckpointsDeployer`

- `JB721CheckpointsDeployer.deploy(hook)` (`JB721CheckpointsDeployer.sol:51-56`). Reverts `JB721CheckpointsDeployer_Unauthorized` unless `msg.sender == hook`. Uses CREATE2 with `hook` as salt so clones land at the same address across chains.
- `JB721Checkpoints.initialize(hookAddress)` (`JB721Checkpoints.sol:114-118`). One-shot; the implementation pre-sets `hook = address(1)` in its constructor (`JB721Checkpoints.sol:68`).
- `JB721Checkpoints.onTransfer(from, to, tokenId)` (`JB721Checkpoints.sol:125-153`). Hook-only. For `from != address(0)` it pushes an owner checkpoint and updates the per-tier eligible-units trace (add on a never-enrolled token's first transfer, subtract on burn of an eligible token), then moves voting units between `from` and `to`. On mint (`from == address(0)`) it writes neither trace — the mint path adds no checkpoint gas.
- `JB721Checkpoints.delegate(delegatee, tokenIds[])` (`JB721Checkpoints.sol:81-109`). Delegates voting power; also enrolls each token by writing an owner checkpoint and adding its tier voting units to the per-tier eligible-units trace, but only if the caller currently owns the token and the token has no checkpoint yet.
- `JB721Checkpoints.getPastTierVotingUnits(tierId, blockNumber)` (`JB721Checkpoints.sol:160-171`). The per-tier analogue of `getPastTotalSupply`: returns the tier's total eligible voting units at a past block, where "eligible" means tokens with an owner checkpoint (enrolled or transferred at least once). Distributors use it as the denominator for tier-scoped reward pots. Mints never contribute to it.
- `JB721Checkpoints.ownerOfAt(tokenId, blockNumber)` (`JB721Checkpoints.sol:179-193`). Returns `address(0)` for tokens that have never been enrolled or transferred — those tokens are ineligible for snapshot-based distribution.

---

## Section D — Cross-cutting invariants

- **Tier-price immutability post-creation.** `storedTier.price` is never re-assigned after `recordAddTiers`. Discounts modify what payers pay; they never change cash-out weight.
- **Removed-tier NFTs remain cash-outable.** Tier removal (`recordRemoveTierIds`) only flips a removal bitmap; it does NOT subtract from the `totalCashOutWeightOf` aggregate (`JB721TiersHookStore.sol:1138-1162` only adjusts the aggregate on mint/burn), so a removed tier's already-minted NFTs still contribute and their pending reserves still count.
- **Category sort is strict-monotonic-or-equal.** `recordAddTiers` reverts `JB721TiersHookStore_InvalidCategorySortOrder` whenever a new tier's category is less than the previous tier's (`JB721TiersHookStore.sol:952-961`). Same-category appends are inserted before older same-category tiers; the linked-list rewires `_startingTierIdOfCategory` to point at the newer tier (`JB721TiersHookStore.sol:1049-1051`).
- **Reserve frequency math.** `pendingReserves = ceil(numberOfNonReserveMints / reserveFrequency) − numberOfReservesMintedFor` (`JB721TiersHookStore.sol:712-755`). `reserveFrequency` is immutable; deadlock case (`initialSupply == 1 && reserveFrequency > 0`) is rejected at tier creation (`JB721TiersHookStore.sol:1004-1008`).
- **Store trusts `msg.sender == hook`.** Every mutating store function keys all writes by `msg.sender`, so corruption is confined to the calling hook's namespace. The flip side: a malicious or buggy hook can corrupt only ITS OWN tier state.
- **Hook authenticates terminal callbacks.** Both pay and cash-out callbacks check `DIRECTORY.isTerminalOf(projectId, msg.sender)` (`abstract/JB721Hook.sol:202-209, 251-258`).
- **`hasMintPermissionFor` is hardcoded to `false`.** This hook never grants `JBController` permission to mint project tokens on the payer's behalf — only the standard terminal pay path mints (`abstract/JB721Hook.sol:150-152`).
- **Forwarded amount must match attached ETH.** RISKS §6 "Forwarded funds must match split metadata" — the hook rejects native-token msg.value/forwardedAmount mismatch, ERC-20 calls with attached ETH, missing split metadata for non-zero forwarded amounts, and split metadata whose amounts don't sum to the forwarded amount.
- **Token ID encoding is global.** `tokenId / 1e9 = tierId`, `tokenId % 1e9 = tokenNumber` (`JB721TiersHookStore.sol:515-517`). Cap of `1e9 − 1` per-tier supply prevents tokens from overflowing into the next tier (`JB721TiersHookStore.sol:946-948`).
- **Pay credits are off-chain-balance-only.** `payCreditsOf[beneficiary]` is incremented from leftover at mint time and decremented when a later mint applies them. No transfer/claim mechanism exists; credits are non-transferable and have no cap. RISKS §2.

---

## Section E — Centralization posture

- **Hook clone — `JBOwnable`, scoped to project owner.** Each clone's owner is the project NFT holder (after `transferOwnershipToProject`). All powerful mutators (`adjustTiers`, `mintFor`, discount, metadata) gate through `_requirePermissionFrom({account: owner(), ...})`. The project owner can therefore delegate any of these surfaces to operators via the core `JBPermissions` registry; there is no super-admin override on the hook.
- **Store — no admin.** `JB721TiersHookStore` has no owner, no upgrade path, no privileged caller. It trusts `msg.sender` to be a hook and writes scoped to that hook's address. Global admin actions across all hooks are not possible.
- **Project deployer — permissionless launch surface.** `JB721TiersHookProjectDeployer.launchProjectFor` is fully permissionless (any caller can launch a new project + hook pair). `launchRulesetsFor` and `queueRulesetsOf` require the caller to hold the relevant Juicebox permission on the project owner.
- **Hook deployer — permissionless clone factory.** Anyone may call `deployHookFor`, but the resulting hook is immediately owned by the caller (and the canonical Project Deployer atomically reassigns ownership to the project before returning to the user).
- **Checkpoints deployer — hook-gated.** Only the calling hook can deploy its own checkpoint module (`msg.sender == hook` check in `deploy`).
- **No protocol fee or beneficiary on top of core.** This repo adds no fees on top of the 2.5% protocol fee taken by `JBMultiTerminal` on the underlying pay / payout / cash-out flow.

---

## Section F — File:line references

| Claim | File | Line(s) |
|---|---|---|
| Tier price written once | `src/JB721TiersHookStore.sol` | 1020-1036 |
| `cashOutWeightOf` uses original price | `src/JB721TiersHookStore.sol` | 478-491 |
| `totalCashOutWeightOf` aggregate includes pending reserves | `src/JB721TiersHookStore.sol` | 1276 |
| `recordMint` reserve-vs-remaining check | `src/JB721TiersHookStore.sol` | 1277-1283 |
| `recordSetDiscountPercentOf` monotonicity | `src/JB721TiersHookStore.sol` | 1394-1398 |
| Category sort enforcement | `src/JB721TiersHookStore.sol` | 952-961 |
| Reserve frequency math | `src/JB721TiersHookStore.sol` | 712-755 |
| `recordRemoveTierIds` blocks `cantBeRemoved` | `src/JB721TiersHookStore.sol` | 1356-1359 |
| Token ID encoding | `src/JB721TiersHookStore.sol` | 515-517, 593-595 |
| `useReserveBeneficiaryAsDefault` overwrite warning | `src/JB721TiersHookStore.sol` | 1055-1062 |
| `cleanTiers` compacts removed trailing suffix | `src/JB721TiersHookStore.sol` | 882-894 |
| `JB721TiersHook.initialize` one-shot | `src/JB721TiersHook.sol` | 247-314 |
| `adjustTiers` permission | `src/JB721TiersHook.sol` | 351-353 |
| `mintFor` permission + allowOwnerMint | `src/JB721TiersHook.sol` | 373-392 |
| `setDiscountPercentOf` permission | `src/JB721TiersHook.sol` | 417-422 |
| `setMetadata` permission | `src/JB721TiersHook.sol` | 458-471 |
| `mintPendingReservesFor` permissionless + pause check | `src/JB721TiersHook.sol` | 518-526 |
| Transfer pause: per-tier AND ruleset | `src/JB721TiersHook.sol` | 769-783 |
| First-owner recorded once | `src/JB721TiersHook.sol` | 786-787 |
| Lazy checkpoint deploy on first transfer | `src/JB721TiersHook.sol` | 794-799 |
| Payer ≠ beneficiary: no credit | `src/libraries/JB721TiersHookLib.sol` | 236-240 |
| `cantBuyWithCredits` enforcement | `src/libraries/JB721TiersHookLib.sol` | 253-255 |
| `preventOverspending` enforcement | `src/libraries/JB721TiersHookLib.sol` | 259-261 |
| Sucker beneficiary substitution | `src/JB721TiersHook.sol` | 702-711 |
| Pay hook ETH-attached check | `src/abstract/JB721Hook.sol` | 262-269 |
| Cash-out: terminal-only + msg.value==0 | `src/abstract/JB721Hook.sol` | 197-209 |
| Cash-out rejects mixed fungible | `src/abstract/JB721Hook.sol` | 97-100 |
| `hasMintPermissionFor` returns false | `src/abstract/JB721Hook.sol` | 150-152 |
| Pay callback terminal auth | `src/abstract/JB721Hook.sol` | 251-258 |
| Project deployer `launchRulesetsFor` permissions | `src/JB721TiersHookProjectDeployer.sol` | 144-156 |
| Project deployer `queueRulesetsOf` permission | `src/JB721TiersHookProjectDeployer.sol` | 199-203 |
| Project deployer `launchProjectFor` permissionless + msg.value forwarding | `src/JB721TiersHookProjectDeployer.sol` | 81-114 |
| Project deployer salt rebinding | `src/JB721TiersHookProjectDeployer.sol` | 101, 162, 209 |
| Hook deployer permissionless + registry | `src/JB721TiersHookDeployer.sol` | 71-116 |
| CheckpointsDeployer hook-only auth | `src/JB721CheckpointsDeployer.sol` | 51-56 |
| Checkpoints `onTransfer` hook-only | `src/JB721Checkpoints.sol` | 125-153 |
| Checkpoints per-tier eligible-units trace (`getPastTierVotingUnits`) | `src/JB721Checkpoints.sol` | 53-57, 160-171 |
| Checkpoints mint writes no trace (no added mint gas) | `src/JB721Checkpoints.sol` | 131-133 |
| Discount denominator = 200 | `src/libraries/JB721Constants.sol` | 7 |
| Hook-wide flags definition | `src/structs/JB721TiersHookFlags.sol` | 14-20 |
| Tier flags definition | `src/structs/JB721TierFlags.sol` | 8-14 |

---

## Out of scope

- Underlying core terminal/controller/permissions/sucker guarantees — see `../INVARIANTS.md` and `nana-core-v6`.
- Project-specific token URI resolvers (Banny, Defifa) and the resolver trust surface — those live downstream and are described in their own repos.
- Croptop's curator surface that composes over this hook.
- The 2.5% protocol fee mechanics — inherited from `JBMultiTerminal`.
