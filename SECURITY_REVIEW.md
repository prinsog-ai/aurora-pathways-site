# Smart Contract Security Review — Aurora Pathways / Polygon Mainnet

**Date:** June 10, 2026  
**Scope:** 4 production contracts (TaskEscrowV2, PledglyV2, Forekast, RideP2P)  
**Compiler:** Solidity ^0.8.20 / ^0.8.28  
**Auditor:** Hermes Agent (automated review)

---

## Executive Summary

| Contract | Critical | High | Medium | Low |
|---|---|---|---|---|
| TaskEscrowV2 | 0 | 2 | 3 | 3 |
| PledglyV2 | 0 | 1 | 3 | 2 |
| Forekast | **1** | **1** | 2 | 1 |
| RideP2P | 0 | **2** | 3 | 2 |

**The Forekast contract has a CRITICAL fee-accounting bug that will cause funds to become permanently stuck after multiple winners claim.** The RideP2P contract lacks ReentrancyGuard and has a griefing vector via disputes. All contracts use OpenZeppelin correctly and benefit from Solidity 0.8+ overflow protection.

---

## 1. TaskEscrowV2.sol (550 lines)

*Freelance marketplace: milestone-based escrow, 3% platform fee, 3-of-5 jury disputes*

### OpenZeppelin Usage: ✅ Correct
- `IERC20`, `SafeERC20`, `Ownable(msg.sender)`, `ReentrancyGuard` — all properly imported and inherited.
- `nonReentrant` on all functions with external transfers: `createJob`, `releaseMilestone`, `cancelJob`, `claimRefund`, `voteDispute`.

### HIGH Issues

**H-T1: `claimRefund` has no access control — anyone can trigger refund after deadline**
- **Lines 305-325:** The comment says "Anyone can claim a refund" and the code confirms it — there is no `msg.sender == job.client` check.
- **Impact:** A competing freelancer, MEV bot, or malicious actor can front-run the client after `deadline` passes, force-setting the job to `Cancelled` and refunding un-released milestones. This prevents the client from waiting for late delivery or negotiating with the freelancer.
- **Funds at risk:** None directly (funds go to `job.client`), but the job lifecycle is forcibly terminated.
- **Fix:** Add `require(msg.sender == job.client || msg.sender == job.freelancer)` or at minimum `require(msg.sender == job.client)`.

**H-T2: Owner can replace jurors mid-dispute**
- **Lines 136-148:** `setJuror` allows the owner to swap any jury slot at any time, with no timelock.
- **Impact:** If a dispute is active, the owner could stack the jury with colluding addresses to control the outcome. This is a centralization/rug-pull risk.
- **Fix:** Freeze jury changes while any job is in `Disputed` status, or add a timelock with event-based notification.

### MEDIUM Issues

**M-T1: `setPlatformTreasury` emits no event (line 130-133)**
- Treasury changes are invisible on-chain. Off-chain monitors cannot detect redirection of fee payments.
- **Fix:** Add `emit PlatformTreasuryUpdated(_treasury);`

**M-T2: `platformFee` is mutable, affects in-progress jobs retroactively (line 124-128)**
- Owner can raise fee from 3% to 10% mid-job. A freelancer who accepted expecting 3% fee now gets less.
- **Fix:** Lock fee at job creation time (store per-job fee).

**M-T3: O(n) linear scans for applicants — gas griefing (lines 221, 236)**
- `applyToJob` and `acceptFreelancer` iterate the full `applicants[]` array. If spammed with thousands of applicants, these functions become prohibitively expensive.
- **Fix:** Use `mapping(address => bool)` for applicant tracking alongside the array.

### LOW / Informational

- **L-T1:** Milestone amount can be 0 (line 181) — no per-milestone validation.
- **L-T2:** No maximum milestone count — a job with 1000 milestones would make `createJob` very expensive.
- **L-T3:** `getJobs` view function (line 466) returns massive memory arrays — could hit gas limits in on-chain calls.

---

## 2. PledglyV2.sol (348 lines)

*Creator subscription platform: USDC payments, NFT proof-of-subscription, 3% fee*

### OpenZeppelin Usage: ✅ Correct
- `ERC721`, `Ownable`, `ReentrancyGuard`, `SafeERC20` — properly used.
- `nonReentrant` on `subscribe`, `renew`, `withdrawPlatformFees`.
- `_safeMint` used instead of `_mint` (line 194) — correct for safe recipient checks.

### HIGH Issues

**H-P1: `isSubscribedTo` mapping is broken for multi-tier subscriptions**
- **Line 205:** `isSubscribedTo[msg.sender][_creatorId] = true;` — set on ANY subscription.
- **Line 246:** `isSubscribedTo[msg.sender][sub.creatorId] = false;` — cleared on ANY cancellation.
- **Scenario:** User subscribes to Creator A (Tier 1), then subscribes again (Tier 2). Cancels Tier 1 → `isSubscribedTo` set to `false` despite still having an active Tier 2 subscription.
- **Impact:** External contracts relying on `isSubscribedTo` for token-gating will incorrectly deny access. The internal `canAccessContent` / `getContentURI` functions are unaffected (they iterate `userTokens` directly).
- **Fix:** Count active subscriptions per creator instead of using a bool:
  ```solidity
  mapping(address => mapping(uint256 => uint256)) public activeSubCount;
  // Increment on subscribe, decrement on cancel. Check > 0.
  ```

### MEDIUM Issues

**M-P1: `withdrawPlatformFees` is dead code — contract never holds USDC (lines 340-347)**
- Fees are transferred directly from subscriber → `owner()` via `safeTransferFrom` (line 189, 225). The contract itself never receives USDC.
- `usdc.balanceOf(address(this))` will always be 0. The `totalPlatformFees` variable is misleading.
- **Impact:** No funds at risk, but the code is confusing and `totalPlatformFees` is inaccurate.
- **Fix:** Either route fees through the contract (transferFrom → contract → owner) or remove `withdrawPlatformFees` and `totalPlatformFees`.

**M-P2: `updateTier` has no ownership validation on tier ID (line 157-163)**
- Creator A can call `updateTier(tierId_from_creator_B, false)` — it silently sets `tiers[creatorA][thatId].active = false` on a non-existent tier. No harm, but poor validation.
- **Fix:** Verify `tiers[creatorId][_tierId]` exists (e.g., check name is non-empty or add an `exists` flag).

**M-P3: `postContent` doesn't validate `_minTierId` (line 254-276)**
- Creator can post content with `_minTierId = 999` — no subscriber could ever access it.
- **Fix:** Require `_minTierId <= nextTierId[creatorId] - 1`.

### LOW / Informational

- **L-P1:** `canAccessContent` (line 289) iterates all user tokens — O(n) per-user. Could hit gas limits if called on-chain by another contract.
- **L-P2:** No mechanism for creators to transfer their registration to a new address if wallet is compromised.

---

## 3. Forekast.sol (167 lines) ⚠️ MOST CRITICAL

*Prediction/betting market: USDC bets, Yes/No outcomes, 3% platform fee*

### OpenZeppelin Usage: ✅ Correct

### CRITICAL Issues

**C-F1: Fee accounting is double-counted — funds will be permanently stuck**
- **Lines 130-131:** Fee is calculated from `loserTotal` (a fixed market-level value).
- **Line 151:** `totalFees += fee;` is executed **once per winner**, not once per market.
- **Scenario with 2 winners:**
  - Market: `totalYes = 1000` (Alice=600, Charlie=400), `totalNo = 1000` (Bob). Outcome: Yes.
  - Fee = 30, prizePool = 970
  - Alice claims: payout = 1182. Contract balance: 2000→818. `totalFees = 30`.
  - Charlie claims: payout = 788. Contract balance: 818→30. `totalFees = 60`.
  - Owner calls `withdrawFees()`: tries to transfer 60, but contract only has 30 → **REVERTS**.
  - **30 USDC is permanently locked in the contract.**
- **Root cause:** The fee (30) exists only once in the pool but is counted N times.
- **Fix:** Either:
  1. Track `remainingLoserPool` that decreases with each claim, and recalculate fee from remaining pool.
  2. Better: pre-compute and store the fee once at resolution time:
  ```solidity
  // In resolveMarket or first claim:
  uint256 marketFee = (loserTotal * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
  uint256 marketPrizePool = loserTotal - marketFee;
  // Store these per-market. On each claim:
  uint256 payout = (userBet * (winnerTotal + marketPrizePool)) / winnerTotal;
  // Only add fee to totalFees once:
  if (!feeCollected[marketId]) { totalFees += marketFee; feeCollected[marketId] = true; }
  ```

### HIGH Issues

**H-F1: Market creator can resolve their own market — rug pull vector**
- **Line 102:** `require(msg.sender == owner() || msg.sender == market.creator, "Not authorized")`
- **Scenario:** Attacker creates market with 1 USDC initial liquidity on Yes. Collects 10,000 USDC in No bets from victims. Resolves "Yes" — takes 10,000 USDC minus fees.
- **Impact:** Complete loss of funds for bettors. This is the classic prediction market rug pull.
- **Fix:** Resolution should require an independent oracle (Chainlink), multi-sig, or DAO vote. Remove `market.creator` from authorized resolvers.

### MEDIUM Issues

**M-F1: No minimum resolution deadline validation (line 56)**
- Creator can set `_resolutionDeadline = block.timestamp + 1`, making the market immediately resolvable after creation. Combined with H-F1, this enables instant rug pulls.
- **Fix:** Enforce minimum deadline (e.g., `_resolutionDeadline >= block.timestamp + 1 days`).

**M-F2: `withdrawFees()` lacks `nonReentrant` (line 156-162)**
- State is updated before transfer (`totalFees = 0`), following checks-effects-interactions. Safe in practice, but violates defense-in-depth.
- **Fix:** Add `nonReentrant` modifier.

### LOW / Informational

- **L-F1:** No mechanism to handle market ties or invalid outcomes (e.g., event cancelled). Bettors' funds would be stuck.
- **L-F2:** No bet limits — whale could dominate a market.

---

## 4. RideP2P.sol (381 lines)

*Ride-sharing marketplace: USDC escrow, driver payouts, dispute resolution*

### OpenZeppelin Usage: ⚠️ Missing ReentrancyGuard
- `IERC20`, `SafeERC20`, `Ownable` imported, but **`ReentrancyGuard` is NOT imported or inherited**.
- Multiple functions make external USDC transfers without reentrancy protection.

### HIGH Issues

**H-R1: No ReentrancyGuard — defense-in-depth failure**
- **Affected functions:** `completeRide` (L167), `cancelBooking` (L198), `driverCancelRide` (L216), `resolveDispute` (L266).
- All make external `safeTransfer` calls. While standard USDC has no callbacks, this violates best practice and creates vulnerability if the contract is ever adapted for other tokens.
- **Fix:** Import and inherit `ReentrancyGuard`, add `nonReentrant` to all functions with external transfers.

**H-R2: Dispute can be opened on Active rides — griefing vector**
- **Line 235:** `require(ride.status == RideStatus.Active || ride.status == RideStatus.Completed, ...)`
- A rider can call `openDispute` on an `Active` ride, changing status to `Disputed` (line 252). This prevents the driver from calling `completeRide` (which requires `Active` status). Funds are then stuck in escrow until the owner resolves.
- **Scenario:** Rider books ride, then disputes before departure to freeze driver's earnings indefinitely.
- **Fix:** Either restrict disputes to `Completed` rides only, or add a time-based auto-resolution mechanism.

### MEDIUM Issues

**M-R1: Driver can complete ride immediately — no departure check (line 167)**
- `completeRide` only checks `rideIsActive` and `bookedSeats > 0`. No check that `departureTime` has passed.
- A driver could create a ride, receive bookings, then immediately complete it and pocket all funds without providing any service.
- **Fix:** Add `require(block.timestamp >= rides[rideId].departureTime, "Too early");` or a reasonable buffer.

**M-R2: Full centralization on dispute resolution (line 266)**
- Only `owner()` can resolve disputes. No jury, no community vote, no timeout.
- If the owner is compromised or unresponsive, all disputed funds are permanently locked.
- **Fix:** Add a fallback mechanism (e.g., auto-refund after 30 days if unresolved).

**M-R3: `driverRatedForRide` allows only ONE rider to rate per ride (line 73, 320)**
- In multi-rider rides, only the first rider to call `rateDriver` gets to rate. Other riders' ratings are blocked.
- **Fix:** Use `mapping(uint256 => mapping(address => bool))` to track per-rider ratings.

### LOW / Informational

- **L-R1:** `verifiedDrivers` is set by owner but never enforced — anyone can create rides regardless of verification status.
- **L-R2:** `DisputeResolved` event (line 82) doesn't include payout amounts, making off-chain accounting difficult.
- **L-R3:** No maximum seats validation — a driver could create a ride with `totalSeats = 2^256 - 1`.

---

## Cross-Contract Concerns

### Centralization Risks (All Contracts)
| Contract | Owner Powers | Risk Level |
|---|---|---|
| TaskEscrowV2 | Change fees (up to 10%), replace jurors, change treasury | HIGH |
| PledglyV2 | Withdraw (empty) fees, standard admin | LOW |
| Forekast | Resolve markets unilaterally, withdraw fees | CRITICAL |
| RideP2P | Resolve disputes, verify drivers | HIGH |

**Recommendation:** Implement a multi-sig (Gnosis Safe) as the owner for all contracts. Consider timelocks for fee changes.

### Gas Considerations
- TaskEscrowV2: O(n) loops on applicants and milestones — could hit block gas limit with spam.
- PledglyV2: `canAccessContent` O(n) loop on user tokens — fine for off-chain, risky for on-chain.
- RideP2P: `driverCancelRide` refunds in a loop — could hit gas limit with many bookings.
- Forekast: `claimWinnings` is O(1) — no gas concerns. ✅

### Event Emission Audit
| Contract | Missing Events |
|---|---|
| TaskEscrowV2 | `setPlatformTreasury` — no event |
| PledglyV2 | `updateCreatorProfile` — no event |
| Forekast | All state changes emit events ✅ |
| RideP2P | All state changes emit events ✅ |

---

## Priority Fix List

1. 🔴 **CRITICAL — Forekast C-F1:** Fix fee accounting before any more markets resolve. Funds are at risk of permanent lockup.
2. 🔴 **CRITICAL — Forekast H-F1:** Remove market creator from `resolveMarket` authorization. Use an oracle or multi-sig.
3. 🟠 **HIGH — RideP2P H-R1:** Add `ReentrancyGuard` import and `nonReentrant` to all transfer functions.
4. 🟠 **HIGH — RideP2P H-R2:** Restrict `openDispute` to `Completed` rides or add auto-resolution timeout.
5. 🟠 **HIGH — TaskEscrowV2 H-T1:** Add access control to `claimRefund`.
6. 🟠 **HIGH — TaskEscrowV2 H-T2:** Freeze jury during active disputes.
7. 🟡 **MEDIUM — PledglyV2 H-P1:** Fix `isSubscribedTo` bool → counter.
8. 🟡 **MEDIUM — RideP2P M-R1:** Add departure time check to `completeRide`.
9. 🟡 **MEDIUM — Forekast M-F1:** Enforce minimum resolution deadline.
10. 🟡 **MEDIUM — All:** Move to multi-sig ownership for production deployment.

---

*This review is automated and does not replace a professional manual audit. Consider engaging a formal audit firm (Trail of Bits, OpenZeppelin, Consensys Diligence) before handling significant TVL.*
