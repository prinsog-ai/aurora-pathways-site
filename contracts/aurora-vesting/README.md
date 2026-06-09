# TokenVesting

Linear token vesting with cliff for the Aurora Pathways ecosystem. Owner creates vesting schedules for beneficiaries who claim vested tokens over time.

## Contract

**TokenVesting** (`src/TokenVesting.sol`) — inherits OpenZeppelin `Ownable` + `ReentrancyGuard`.

- **Token**: Any ERC-20 (configured at deploy time, immutable)
- **Schedule Creation**: Owner-only, transfers tokens from owner to contract
- **Cliff**: Configurable per schedule (0 = no cliff, linear vesting from start)
- **Vesting**: Linear unlock over configurable duration
- **Revocation**: Owner can revoke revocable schedules, returning unvested tokens
- **Claiming**: Anyone can trigger a claim on behalf of any beneficiary
- **Tracking**: Per-beneficiary schedule lists, per-schedule claim tracking

## Gas Report

| Function | Min | Avg | Median | Max |
|---|---|---|---|---|
| `deploy` | — | — | — | 1,408,963 |
| `createSchedule` | 25,628 | 231,038 | 252,515 | 272,463 |
| `claim` | 29,438 | 91,604 | 115,024 | 119,824 |
| `revoke` | 24,156 | 62,324 | 72,276 | 85,705 |
| `vestedAmount` | 7,265 | 12,384 | 12,863 | 15,102 |
| `claimableAmount` | 15,209 | 15,397 | 15,491 | 15,491 |

## Build & Test

```shell
source ~/.zshenv
forge build
forge test -vvv
forge test --gas-report
```

## Deploy

```shell
source ~/.zshenv
cp .env.example .env   # fill in PRIVATE_KEY, TOKEN_ADDRESS, OWNER_ADDRESS, RPC_URL
forge script script/Deploy.s.sol:DeployTokenVesting \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

## Verify

```shell
forge verify-contract \
  --chain-id 11155111 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address,address)" "$TOKEN_ADDRESS" "$OWNER_ADDRESS") \
  DEPLOYED_ADDRESS \
  src/TokenVesting.sol:TokenVesting
```

## Project Structure

```
aurora-vesting/
├── src/TokenVesting.sol       # Vesting contract
├── test/TokenVesting.t.sol    # Tests (37 tests)
├── script/Deploy.s.sol        # Deployment script
├── lib/                       # Dependencies (OpenZeppelin, forge-std)
├── .env.example               # Required env vars (no values)
└── README.md
```

## Dependencies

- OpenZeppelin Contracts v5.x (`@openzeppelin/contracts`)
- Foundry (forge, cast, anvil)