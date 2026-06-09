# AuroraNFT — ERC-721 NFT Collection for Aurora Pathways

Mintable NFT collection with configurable pricing, Merkle whitelist, EIP-2981 royalties, and reveal mechanics. Built for the Aurora Pathways ecosystem.

## Features

| Feature | Details |
|---|---|
| **Public Mint** | Configurable per-token price in native ETH/MATIC |
| **Whitelist Mint** | Merkle-proof verified, discounted price |
| **Owner Mint** | Free mint for team/marketing |
| **Royalties** | EIP-2981 secondary sale royalties (configurable, max 10%) |
| **Reveal** | Pre-reveal placeholder URI → post-reveal metadata base URI |
| **Supply Cap** | Immutable max supply set at deploy |
| **Per-Wallet Limit** | Configurable cap across public + whitelist mints |
| **Enumerable** | ERC-721 Enumerable for on-chain enumeration |

## Quick Start

```bash
source ~/.zshenv
cd contracts/aurora-nft

# Compile
forge build

# Run tests
forge test -vvv

# Gas report
forge test --gas-report
```

## Deploy

```bash
cp .env.example .env
# Edit .env with your values

source .env
forge script script/Deploy.s.sol:DeployAuroraNFT \
  --rpc-url $AMOY_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

## Contract Parameters

| Parameter | Constructor | Changeable? |
|---|---|---|
| Name / Symbol | Yes | No |
| Max Supply | Yes | No |
| Public Price | Yes | Yes (owner) |
| Whitelist Price | Yes | Yes (owner) |
| Max Per Wallet | Yes | Yes (owner) |
| Royalty Receiver | Yes | Yes (owner) |
| Royalty BPS | Yes | Yes (owner, max 1000 = 10%) |
| Merkle Root | No (set after) | Yes (owner) |
| Pre-reveal URI | No (set after) | Yes (owner) |
| Base URI (reveal) | No (set on reveal) | One-time (owner) |

## Test Coverage

| Area | Tests |
|---|---|
| Deployment & initial state | 10 |
| Public mint | 8 |
| Whitelist mint (Merkle) | 7 |
| Owner mint | 3 |
| Reveal mechanics | 5 |
| Royalties (EIP-2981) | 5 |
| Configuration (owner gating) | 4 |
| Withdraw | 3 |
| ERC-721 enumeration | 3 |
| Transfers | 1 |
| Mixed scenarios | 3 |
| **Total** | **52** |

## Project Structure

```
aurora-nft/
├── src/
│   └── AuroraNFT.sol
├── test/
│   └── AuroraNFT.t.sol
├── script/
│   └── Deploy.s.sol
├── lib/
│   ├── forge-std/
│   └── openzeppelin-contracts/
├── foundry.toml
├── remappings.txt
├── .env.example
└── README.md
```
