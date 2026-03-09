# nana-721-hook-v6 — Risks

## Trust Assumptions

1. **Project Owner** — Can adjust tiers (add/remove), set metadata resolver, set discount percent, and configure hook flags. Full control over NFT economics.
2. **Core Protocol** — Relies on JBMultiTerminal and JBController to correctly call pay/cashout hooks. Hook only executes in response to core protocol calls.
3. **Token URI Resolver** — If set, has full control over NFT metadata rendering. Cannot affect funds but can misrepresent NFT properties.
4. **Store Contract** — JB721TiersHookStore manages all tier state. Hook delegates pricing and supply logic to the store.

## Known Risks

| Risk | Description | Mitigation |
|------|-------------|------------|
| Category sort order | Tiers must be sorted by category when added — store reverts `InvalidCategorySortOrder` if violated | Validate tier ordering off-chain before submitting |
| 100% discount | Setting `discountPercent = 200` allows free minting with full cash-out weight | Only set intentionally; monitor discount configurations |
| Tier removal is soft | Removed tiers are flagged, not deleted — existing NFTs from removed tiers retain cash-out weight | By design; prevents retroactive value destruction |
| Cash-out weight truncation | Integer division `weight/tokens` can permanently lock dust amounts | Bounded to ~1 wei per tier per operation |
| Large tier arrays | Many tiers increase gas for operations that iterate tiers | Keep tier count manageable |
| Metadata decode failure | If payment metadata is malformed, hook may skip NFT minting | Use `JBMetadataResolver` for encoding |

## Privileged Roles

| Role | Permissions | Scope |
|------|------------|-------|
| Project owner | `ADJUST_721_TIERS`, `SET_721_METADATA`, `SET_721_DISCOUNT_PERCENT` | Per-project |
| JBDirectory | Routes hook calls from terminal | Protocol-wide |

## External Dependencies
- **JBMultiTerminal** — Calls hook during pay/cashout; hook trusts caller is terminal
- **JBController** — Validates project ownership for tier adjustments
- **JBPermissions** — Permission checks for tier management operations
