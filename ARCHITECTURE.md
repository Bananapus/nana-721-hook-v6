# Architecture

## Purpose

`nana-721-hook-v6` adds tiered NFT behavior to Juicebox projects. It lets a project accept payments, mint NFTs from configured tiers, optionally accumulate NFT credits, lazily mint reserves, and, when enabled, let holders burn NFTs to cash out project surplus according to tier-defined economics.

## Boundaries

- `JB721TiersHook` owns tier-aware behavior.
- `JB721TiersHookStore` owns compact tier storage and many validation rules.
- `JB721TiersHookDeployer` and `JB721TiersHookProjectDeployer` own deployment and project-launch convenience.
- The repo does not replace the core terminal, controller, or surplus logic; it plugs into them.

## Main Components

| Component | Responsibility |
| --- | --- |
| `JB721TiersHook` | Data hook, pay hook, and cash-out hook for tiered NFTs |
| `JB721TiersHookStore` | Packed tier storage, mint accounting, reserves, and validation |
| `JB721Hook`, `ERC721` | Shared NFT machinery and token metadata plumbing |
| deployers | Clone and launch helpers for hook instances and projects |
| libraries and structs | Tier math, metadata decoding, flags, and config surfaces |

## Runtime Model

### Payment Path

```text
terminal payment
  -> data hook inspects metadata and requested tier IDs
  -> hook computes which tiers can be minted and how much value is left over
  -> terminal settles the payment into the project
  -> pay hook mints NFTs and stores any remaining value as credits when allowed
```

### Reserve Path

```text
tier purchases accumulate reserve entitlement
  -> reserves are minted lazily via explicit reserve-mint calls
```

### Cash-Out Path

```text
holder burns NFT
  -> data hook can override cash-out count, supply, and tax behavior
  -> reclaim value is based on the tier's original configured price, not any discount used at mint time
```

## Critical Invariants

- Tiers are an ordered, compact data structure. Category ordering and tier IDs are part of storage semantics, not just metadata.
- Original tier price drives cash-out weight. Discounts change purchase price, not reclaim weight.
- Reserve frequency and owner-mint settings interact; configurations that would double-count mint authority must stay invalid.
- Pending reserves belong in supply-sensitive calculations even before they are lazily minted.
- If `useDataHookForCashOut` is enabled, fungible-token cash outs are intentionally displaced by NFT cash-out semantics.

## Where Complexity Lives

- The store is compact and efficient, which means seemingly small layout changes have wide effects.
- Preview behavior, pay behavior, reserve minting, and cash-out behavior all depend on the same tier semantics.
- Metadata decoding and credit handling create edge cases around partial spends and exact-tier selection.

## Dependencies

- `nana-core-v6` hooks, permissions, controller, and terminal surfaces
- Optional token URI resolvers such as `banny-retail-v6` and `defifa-collection-deployer-v6`

## Safe Change Guide

- Treat store changes as consensus-level changes for every repo that composes this hook.
- Preview behavior and live behavior must stay aligned. If a preview lies, integrators misprice payments.
- Be careful when adding metadata fields; many sibling repos depend on stable encoding conventions.
- Keep hook-order assumptions explicit when this hook is composed with other data hooks through a wrapper deployer.
- If you touch reserve logic, also inspect supply math and cash-out denominators.
