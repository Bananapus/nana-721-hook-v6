# Architecture

## Purpose

`nana-721-hook-v6` is the canonical tiered NFT issuance layer for Juicebox V6. It lets a project mint NFTs on payment, manage tier pricing and supply, accumulate NFT credits, lazily mint reserves, and optionally use NFT-aware cash-out behavior.

## System Overview

`JB721TiersHook` is the project-facing hook surface. Through the shared `JB721Hook` base, it installs itself as both the ruleset data hook and the post-settlement pay and cash-out hook for the project. `JB721TiersHookStore` is the compact storage and validation backend that defines most tier semantics. The deployers package that behavior for existing projects or one-shot launches. The repo composes `nana-core-v6` rather than replacing terminal, controller, or surplus accounting.

## Core Invariants

- Tier ordering, category ordering, and tier IDs are part of storage semantics.
- Original configured tier price drives cash-out weight; discounts affect mint price, not reclaim weight.
- Reserve frequency and owner-mint settings must not combine into duplicate mint authority.
- Pending reserves count in supply-sensitive logic before reserve tokens are lazily minted.
- Preview behavior must stay aligned with live mint and cash-out behavior.
- Tier splits can reduce the fungible-token mint weight before terminal settlement unless `issueTokensForSplits` is enabled.
- If `useDataHookForCashOut` is enabled, NFT cash-out semantics intentionally displace fungible-token cash-out behavior.

## Modules

| Module | Responsibility | Notes |
| --- | --- | --- |
| `JB721TiersHook` | Data-hook, pay-hook, and optional cash-out-hook behavior | Project-facing entrypoint |
| `JB721TiersHookStore` | Tier storage, mint accounting, reserves, validation | Storage-critical |
| `JB721Hook`, `ERC721` | Shared NFT machinery and metadata plumbing | Base abstractions |
| `JB721TiersHookDeployer`, `JB721TiersHookProjectDeployer` | Clone and launch helpers | Deployment surface |

## Trust Boundaries

- Treasury accounting, controller semantics, and permissions live in `nana-core-v6`.
- Resolver contracts such as Banny are outside this repo and are part of the trusted metadata surface when configured.
- Hook composition order matters when this hook is wrapped by deployers such as `nana-omnichain-deployers-v6`.

## Critical Flows

### Payment

```text
terminal payment
  -> data hook decodes metadata and requested tiers
  -> hook computes mintable tiers, split forwarding, beneficiary resolution, and leftover value
  -> terminal settles the payment into the project
  -> post-settlement pay hook mints NFTs and may store remaining value as credits
```

### Reserve Minting

```text
tier purchases
  -> accumulate reserve entitlement
  -> reserve-mint call later realizes those pending reserve tokens
```

### Cash Out

```text
holder burns NFT
  -> data hook overrides fungible-token cash-out inputs when enabled
  -> terminal settles the cash out using NFT-derived weight
  -> post-settlement cash-out hook burns the specified NFTs
  -> reclaim value is derived from the tier's original configured price
```

## Accounting Model

The repo owns tier accounting, reserve accounting, credit accounting, and NFT-specific cash-out inputs. It also owns the mapping from hook metadata to NFT mint and burn side effects after terminal settlement. It does not own the canonical treasury ledger, which remains in `nana-core-v6`.

## Security Model

- Store layout changes have repo-wide blast radius because many downstream packages assume stable tier semantics.
- Metadata decoding is part of economic correctness because it chooses tiers, credits, and cash-out behavior.
- Terminal authorization in the base hook is part of the trust model; arbitrary callers must not be able to trigger pay or cash-out hooks.
- Initialization is one-time and ends by transferring ownership to the initializer. Clone deployers and launch flows depend on that handoff being preserved.
- Reserve math and supply math must be reviewed together.

## Safe Change Guide

- Treat store changes as ecosystem-wide changes.
- Keep previews aligned with state-changing behavior.
- If you change split behavior, re-check both NFT mint side effects and the fungible-token weight returned to the terminal.
- When adding metadata fields or flags, update wrapper deployers and downstream integrations in the same change set.
- If reserve logic changes, re-check supply math, reserve minting, and cash-out denominators together.

## Source Map

- `src/JB721TiersHook.sol`
- `src/JB721TiersHookStore.sol`
- `src/JB721TiersHookDeployer.sol`
- `src/JB721TiersHookProjectDeployer.sol`
