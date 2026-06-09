# Aurora Pathways — Smart Contracts

Production-ready Solidity contracts for the Aurora Pathways ecosystem.

## Projects

| Project | Type | Tests | Description |
|---|---|---|---|
| `aurora-token/` | ERC-20 | 35/35 | Mintable, burnable, 1B cap token (AURA) |
| `aurora-payments/` | Payment Splitter | 12/12 | Multi-chain stablecoin payment splitter |
| `aurora-vesting/` | Vesting | 37/37 | Linear token vesting with cliff |
| `aurora-governance/` | DAO Governance | 49/49 | On-chain DAO: governor, timelock, treasury multisig |

## Quick Start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Source environment
source ~/.zshenv

# Build & test
cd aurora-governance
forge build
forge test -v

# Deploy to testnet
# (see individual project READMEs for deploy instructions)
```

## Multi-Chain Deployment

All contracts deploy to Polygon, Base, and Arbitrum using the same Solidity code.

1. Copy `.env.example` to `.env` and fill in your keys
2. Follow the deploy instructions in each project's README

## Chains

| Chain | Gas/tx | Use Case |
|---|---|---|
| Polygon | ~$0.01 | Primary — everyday dApps, tokens |
| Base | ~$0.02 | Consumer apps, Coinbase flow |
| Arbitrum | ~$0.05 | DeFi-heavy clients |

**Deployed addresses:**

| Contract | Network | Address |
|---|---|---|
| TaskEscrow | Polygon Amoy | `0x163ca1C87224cc219644b3AA5f758D7D8182a1EE` |
| USDC (Circle) | Polygon Amoy | `0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582` |
