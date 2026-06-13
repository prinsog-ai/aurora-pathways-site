# Valence Carbon Credit — Smart Contracts

On-chain carbon credit platform for flare gas capture operations.

## Deployed Contracts (Polygon Mainnet — Chain 137)

| Contract | Address |
|----------|---------|
| **ValenceCarbonCredit (VCC)** | [`0x037aE641f9A5c729b4B05007DD3eaeaeC07393D3`](https://polygonscan.com/address/0x037aE641f9A5c729b4B05007DD3eaeaeC07393D3) |
| **ValencePlatform** | [`0x6F80d64Cd5bBC463890205A1aCe9B7955AafcFD5`](https://polygonscan.com/address/0x6F80d64Cd5bBC463890205A1aCe9B7955AafcFD5) |
| **Owner / Admin** | `0x0cB5E0f72D6d62302c5f1Eb4E8bEfF377fB74e66` |

## Architecture

```
┌──────────────────────────────────────┐
│          ValencePlatform             │
│  • Site registration & management    │
│  • MRV data submission & verification│
│  • Auto-split credit distribution    │
│  • Admin / submitter permissions     │
└──────────┬───────────────────────────┘
           │ owns (mints via)
           ▼
┌──────────────────────────────────────┐
│      ValenceCarbonCredit (VCC)       │
│  • ERC-20 (18 decimals)              │
│  • 1 VCC = 1 metric ton CO2          │
│  • 500M max supply                   │
│  • Burnable (credit retirement)      │
└──────────────────────────────────────┘
```

## How It Works

1. **Register Sites** — Admin registers flare gas capture sites with split % (basis points)
2. **Submit MRV Data** — Authorized submitters log gas capture volumes (MCF)
3. **Auto-Calculate** — `CO2 tons = MCF × co2Factor / 10,000` (default factor: 360 = 3.6%)
4. **Auto-Split & Mint** — Credits minted and split between Valence (platform) and site owner
5. **Withdraw** — Valence can withdraw accumulated credits to any address
6. **Retire** — Credit holders can burn tokens to retire carbon credits

## Split Examples (default factor 360)

| MCF Captured | CO2 Credits | 60/40 Split (Valence/Owner) |
|---|---|---|
| 15,200 | 547 | 328 / 219 |
| 80,000 | 2,880 | 1,728 / 1,152 |
| 10,000 | 360 | 216 / 144 |

## Build & Test

```bash
cd contracts/valence-carbon
~/.foundry/bin/forge build
~/.foundry/bin/forge test -vv
```

## Deploy

```bash
# Local (Anvil)
CHAIN=anvil PRIVATE_KEY=0x... OWNER_ADDRESS=0x... \
  ~/.foundry/bin/forge script script/Deploy.s.sol:DeployValence --rpc-url http://127.0.0.1:8545 --broadcast

# Polygon Mainnet
CHAIN=polygon PRIVATE_KEY=0x... OWNER_ADDRESS=0x... \
  ~/.foundry/bin/forge script script/Deploy.s.sol:DeployValence --rpc-url $POLYGON_RPC_URL --broadcast --slow

# Verify on Polygonscan
~/.foundry/bin/forge verify-contract --chain-id 137 --etherscan-api-key $POLYGONSCAN_API_KEY \
  0x037aE641f9A5c729b4B05007DD3eaeaeC07393D3 \
  src/ValenceCarbonCredit.sol:ValenceCarbonCredit
```

## Test Results

**59 tests passing** — covers deployment, site management, MRV submission, credit distribution, splits, access control, edge cases, and full integration workflow.

## Files

```
src/
  ValenceCarbonCredit.sol   — ERC-20 token (VCC)
  ValencePlatform.sol       — Core platform contract
script/
  Deploy.s.sol              — Deployment script (polygon, amoy, anvil)
test/
  ValencePlatform.t.sol     — 59 comprehensive tests
```
