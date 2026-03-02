# nana-721-hook-v5

Tiered ERC-721 NFT pay/cash-out hook for Juicebox V5 projects.

When a project using this hook is paid, NFTs are minted to the payer based on configurable price tiers. Optionally, NFT holders can burn their NFTs to reclaim funds from the project in proportion to the NFT's tier price.

## Architecture

| Contract | Description |
|----------|-------------|
| `JB721TiersHook` | Core hook. Receives payments via `afterPayRecordedWith`, mints tiered NFTs, handles cash outs via `afterCashOutRecordedWith` by burning NFTs. Extends `JB721Hook` (abstract ERC-721 + data/pay/cash-out hook) and `JBOwnable`. |
| `JB721TiersHookStore` | Shared storage for all `JB721TiersHook` instances. Manages tiers, balances, reserves, supply tracking, voting units, and tier removal bitmaps. |
| `JB721TiersHookDeployer` | Deploys minimal clones of `JB721TiersHook` (via Solady `LibClone`) for existing projects. Registers clones in `IJBAddressRegistry`. |
| `JB721TiersHookProjectDeployer` | One-step deployment: creates a Juicebox project and attaches a 721 tiers hook. Supports `launchProjectFor`, `launchRulesetsFor`, and `queueRulesetsOf`. |
| `JB721Hook` (abstract) | Base class implementing `IJBRulesetDataHook`, `IJBPayHook`, and `IJBCashOutHook`. Wires `beforePayRecordedWith` / `beforeCashOutRecordedWith` data hooks and delegates to `_processPayment` / `_didBurn`. |
| `ERC721` (abstract) | Clone-friendly ERC-721 (uses `_initialize` instead of constructor). Based on OpenZeppelin v5 with `_owners` exposed as `internal`. |

### Libraries

| Library | Purpose |
|---------|---------|
| `JBBitmap` | Manages a bitmap for tracking removed tier IDs. Each 256-bit word covers 256 tiers. |
| `JB721TiersRulesetMetadataResolver` | Packs/unpacks per-ruleset 721 metadata (transfers paused, reserve minting paused) into the `JBRulesetMetadata.metadata` field. |
| `JBIpfsDecoder` | Decodes a `bytes32` encoded IPFS hash into a base58 CID string, concatenated with a base URI. |
| `JB721Constants` | Contains `MAX_DISCOUNT_PERCENT = 200`. |

## Install

```bash
npm install @bananapus/721-hook-v5
```

Or with Forge:

```bash
forge install Bananapus/nana-721-hook-v5
```

If using Forge, add `@bananapus/721-hook-v5/=lib/nana-721-hook-v5/` to `remappings.txt` along with remappings for transitive dependencies.

## Develop

Requires [Node.js](https://nodejs.org/) >= 20 and [Foundry](https://github.com/foundry-rs/foundry).

```bash
npm ci && forge install
```

| Command | Description |
|---------|-------------|
| `forge build` | Compile contracts |
| `forge test` | Run tests |
| `forge test --skip "script/*"` | Run tests (skip deploy scripts with build errors) |
| `forge test -vvvv` | Run tests with full traces |
| `forge fmt` | Lint / format |
| `forge coverage` | Generate test coverage report |
| `forge build --sizes` | Get contract sizes |
