# 🔐 Security Review — nana-721-hook-v6

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | ALL / default                                          |
| **Files reviewed**               | `script/Deploy.s.sol` · `script/helpers/Hook721DeploymentLib.sol` · `src/JB721TiersHook.sol`<br>`src/JB721TiersHookDeployer.sol` · `src/JB721TiersHookProjectDeployer.sol` · `src/JB721TiersHookStore.sol`<br>`src/abstract/ERC721.sol` · `src/abstract/JB721Hook.sol` · `src/libraries/JB721Constants.sol`<br>`src/libraries/JB721TiersHookLib.sol` · `src/libraries/JB721TiersRulesetMetadataResolver.sol` · `src/libraries/JBBitmap.sol`<br>`src/libraries/JBIpfsDecoder.sol` · `src/structs/JB721InitTiersConfig.sol` · `src/structs/JB721Tier.sol`<br>`src/structs/JB721TierConfig.sol` · `src/structs/JB721TiersHookFlags.sol` · `src/structs/JB721TiersMintReservesConfig.sol`<br>`src/structs/JB721TiersRulesetMetadata.sol` · `src/structs/JB721TiersSetDiscountPercentConfig.sol` · `src/structs/JBBitmapWord.sol`<br>`src/structs/JBDeploy721TiersHookConfig.sol` · `src/structs/JBLaunchProjectConfig.sol` · `src/structs/JBLaunchRulesetsConfig.sol`<br>`src/structs/JBPayDataHookRulesetConfig.sol` · `src/structs/JBPayDataHookRulesetMetadata.sol` · `src/structs/JBQueueRulesetsConfig.sol`<br>`src/structs/JBStored721Tier.sol` | 
| **Confidence threshold (1-100)** | 75                                                     |

---

## Findings

[90] **1. Pay Credits Let Buyers Bypass Tier Split Payments**

`JB721TiersHook._mintAndUpdateCredits` · Confidence: 90

**Description**
`payCreditsOf` is merged into NFT purchasing power, but tier split payouts are still capped to `context.forwardedAmount.value`, so a buyer can mint a split-bearing tier mostly with credits while paying only a dust-sized fresh split.

**Fix**

```diff
- leftoverAmount += payCredits;
- if (context.hookMetadata.length != 0 && context.forwardedAmount.value != 0) {
-     JB721TiersHookLib.distributeAll(... amount: context.forwardedAmount.value, ...);
- }
+ uint256 creditBackedAmount = context.payer == context.beneficiary ? payCredits : 0;
+ uint256 splitFundingAmount = context.forwardedAmount.value + creditBackedAmountUsedForMint;
+ if (context.hookMetadata.length != 0 && splitFundingAmount != 0) {
+     JB721TiersHookLib.distributeAll(... amount: splitFundingAmount, ...);
+ }
```
---

[90] **2. Failed Early Splits Are Redistributed to Later Recipients**

`JB721TiersHookLib._distributeSingleSplit` · Confidence: 90

**Description**
When an early split payout fails, its amount is added back into `leftoverAmount` before later splits are calculated, so later recipients can receive the failed recipient’s share instead of that value falling back to project balance.

**Fix**

```diff
- if (!_sendPayoutToSplit(...)) {
-     leftoverAmount += payoutAmount;
- }
+ if (!_sendPayoutToSplit(...)) {
+     failedAmount += payoutAmount;
+ }
...
- if (leftoverAmount != 0) {
-     terminal.addToBalanceOf(... leftoverAmount ...);
+ uint256 amountToProject = leftoverAmount + failedAmount;
+ if (amountToProject != 0) {
+     terminal.addToBalanceOf(... amountToProject ...);
```

---

Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [90] | Pay Credits Let Buyers Bypass Tier Split Payments |
| 2 | [90] | Failed Early Splits Are Redistributed to Later Recipients |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **Public Address Registry Can Grief Hook Deployments** — `JB721TiersHookDeployer.deployHookFor` — Code smells: deployment success depends on `JBAddressRegistry.registerAddress`, and the registry is permissionless plus duplicate-registration-reverting — A third party can likely pre-register a predicted hook address and make `deployHookFor` revert at the registry step, but the practical griefing envelope depends on deployment mode and the caller’s ability to retry with a different salt.
- **Shared `_nonce` Can Desync Registry Provenance After Mixed CREATE/CREATE2 Deployments** — `JB721TiersHookDeployer.deployHookFor` — Code smells: `_nonce` is incremented for both deterministic and non-deterministic deployments, while only the CREATE path consumes the deployer nonce the registry models — Mixed deployment modes may cause later saltless registrations to point at the wrong CREATE address, but I did not complete an end-to-end exploit showing downstream trust assumptions being violated.

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
