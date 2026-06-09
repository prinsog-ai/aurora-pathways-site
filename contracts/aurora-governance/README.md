# Aurora Governance — DAO for Aurora Pathways

On-chain governance suite for the Aurora Pathways ecosystem. Token holders propose, vote, and execute protocol decisions with a 2-day timelock safety net.

## Architecture

```
AuroraGovernanceToken (AURAG)        AuroraTreasury (multisig 2-of-3)
        │                                       │
        ├── votes power ──▶ AuroraGovernor ◀── timelock executor
        │                         │
        └─────────────────────────┘
                          AuroraTimelock (2-day delay)
```

| Contract | Purpose | Size (optimized) |
|---|---|---|
| `AuroraGovernanceToken` | ERC-20 + ERC20Votes + ERC20Permit + Ownable | 7,870 B |
| `AuroraGovernor` | OZ Governor with settings, votes, quorum, timelock | 17,306 B |
| `AuroraTimelock` | 2-day minimum delay, roles for governor + treasury | 6,629 B |
| `AuroraTreasury` | Gnosis Safe-style multisig (2-of-3) | 6,343 B |

## Parameters

| Parameter | Value | Notes |
|---|---|---|
| Token supply cap | 1,000,000,000 AURAG | Owner mints up to cap |
| Voting delay | 7,200 blocks (~1 day) | Polygon 2s blocks |
| Voting period | 21,600 blocks (~3 days) | |
| Proposal threshold | 10,000,000 AURAG | 1% of cap |
| Quorum | 4% of circulating supply | Numerator 4, denominator 100 |
| Timelock delay | 2 days (172,800 seconds) | Between passing and execution |
| Treasury threshold | 2 of 3 signers | Configurable |

## Quick Start

```bash
# Requirements: Foundry >= 1.7.1
source ~/.zshenv
cd contracts/aurora-governance

# Install dependencies
forge install

# Compile
forge build

# Run tests (49 tests)
forge test -vvv

# Gas report
forge test --gas-report
```

## Deploy

### 1. Configure environment

```bash
cp .env.example .env
# Edit .env with your values:
#   PRIVATE_KEY=0x...
#   OWNER_ADDRESS=0x...
#   SIGNER_1=0x...
#   SIGNER_2=0x...
#   SIGNER_3=0x...
```

### 2. Deploy to testnet (Polygon Amoy)

```bash
source ~/.zshenv
source .env

forge script script/Deploy.s.sol:DeployAuroraGovernance \
  --rpc-url $AMOY_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $POLYGONSCAN_API_KEY \
  -vvvv
```

### 3. Deploy to Polygon mainnet

```bash
forge script script/Deploy.s.sol:DeployAuroraGovernance \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $POLYGONSCAN_API_KEY \
  -vvvv
```

### 4. Verify on other chains

```bash
# Base
forge script script/Deploy.s.sol:DeployAuroraGovernance \
  --rpc-url $BASE_RPC_URL \
  --broadcast --verify \
  --etherscan-api-key $BASESCAN_API_KEY -vvvv
```

## Contract Details

### AuroraGovernanceToken (AURAG)

ERC-20 governance token with:
- **Voting**: ERC20Votes with delegation and checkpointing
- **Permit**: Gasless approvals via ERC20Permit
- **Ownership**: Owner minting (capped at 1B)
- **Burn**: Any holder can burn their own tokens

### AuroraGovernor

Full OZ Governor combining:
- `GovernorVotes` — voting power from AURAG
- `GovernorVotesQuorumFraction` — quorum as % of supply
- `GovernorCountingSimple` — for/against/abstain (Bravo tally)
- `GovernorSettings` — configurable delay, period, threshold
- `GovernorTimelockControl` — enforced 2-day timelock

All parameters are governance-updatable (requires a passed proposal).

### AuroraTimelock

OZ TimelockController with:
- 2-day minimum delay between proposal passing and execution
- Governor is sole proposer + executor
- Treasury multisig is additional executor + canceller (safety valve)

### AuroraTreasury

Multi-signature wallet:
- Configurable signers and threshold (initial: 2 of 3)
- Any signer can submit a transaction
- Signers confirm; anyone executes when threshold is met
- Governance-controlled signer management
- Receives ETH and ERC-20 tokens

## Test Coverage

49 tests covering:

| Area | Tests | Key scenarios |
|---|---|---|
| Token | 8 | Deployment, mint, burn, delegation, checkpoints |
| Governor | 14 | Settings, proposal lifecycle, voting, quorum, states |
| Timelock | 5 | Delay, role assignments |
| Treasury | 22 | ETH/ERC20, submit, confirm, revoke, execute, governance |

## Gas Report

### Deploy costs (optimizer_runs=200)
| Contract | Gas |
|---|---|
| AuroraGovernanceToken | 1,842,028 |
| AuroraGovernor | 3,956,028 |
| AuroraTimelock | 1,674,225 |
| AuroraTreasury | 1,663,060 |

### Key operations
| Operation | Avg Gas |
|---|---|
| Token mint | 84,694 |
| Token delegate | 95,527 |
| Governor propose | 70,558 |
| Governor castVote | 69,708 |
| Treasury submit | 121,640 |
| Treasury confirm | 51,829 |
| Treasury execute | 64,106 |

## Project Structure

```
aurora-governance/
├── src/
│   ├── AuroraGovernanceToken.sol
│   ├── AuroraGovernor.sol
│   ├── AuroraTimelock.sol
│   └── AuroraTreasury.sol
├── test/
│   └── AuroraGovernance.t.sol
├── script/
│   └── Deploy.s.sol
├── lib/
│   ├── forge-std/
│   └── openzeppelin-contracts/ (v5.6.1)
├── foundry.toml
├── remappings.txt
├── .env.example
└── README.md
```
