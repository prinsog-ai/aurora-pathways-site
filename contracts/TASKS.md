# Aurora Pathways — Contract Task Queue

Harvey-Dev reads this file every run. Top item = highest priority.
Mark complete with `[x]` — agent updates this file when done.

---

## In Progress

- [x] **Valence Carbon Credit** — ERC-20 (VCC) + platform for MRV data, credit issuance, revenue splitting (59 tests)

## Queued

_(empty)_

## Completed

- [x] **AuroraToken** — ERC-20 (AURA), 1B cap, mintable, burnable (35 tests)
- [x] **AuroraPayments** — Stablecoin payment splitter (12 tests)
- [x] **TokenVesting** — Linear vesting with cliff (37 tests)
- [x] **DAO Governance** — AuroraGovernor (OZ Governor + Timelock) + AuroraTreasury (multi-sig)
- [x] **ERC-721 NFT Collection** — Mintable NFT with configurable price, royalties (EIP-2981), reveal mechanics
- [x] **ERC-1155 Multi-Token** — Membership tiers, gaming items, multi-asset (50 tests)
- [x] **Staking Contract** — Stake AURA tokens, earn rewards over time (44 tests)
- [x] **Multi-Sig Factory** — Deploy custom multi-sigs for clients on demand (28 tests)
- [x] **Airdrop/Merkle Distributor** — Gas-efficient ERC-20 airdrop via Merkle proofs (34 tests)
- [x] **Valence Carbon Credit** — ERC-20 (VCC) + platform for MRV data, credit issuance, revenue splitting (59 tests)

---

## Priority Rules

1. Always work top-down — finish the "In Progress" item before starting the next queued item
2. If a new urgent task is added at the top, finish the current step then switch
3. Update this file: mark completed items `[x]`, mark new in-progress items `[ ]` → change to `[-]` while working
