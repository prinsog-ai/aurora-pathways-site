# AuroraToken (AURA)

ERC-20 token for the Aurora Pathways ecosystem. Owner-mintable with a 1 billion supply cap and burnable by any holder.

## Contract

**AuroraToken** (`src/AuroraToken.sol`) — inherits OpenZeppelin `ERC20` + `Ownable`.

- **Name**: Aurora Token
- **Symbol**: AURA
- **Max Supply**: 1,000,000,000 (1 billion) tokens
- **Decimals**: 18
- **Mint**: Owner-only, capped at `MAX_SUPPLY`
- **Burn**: Any holder can burn their own tokens
- **Ownership**: Deployer sets initial owner; owner can transfer via `transferOwnership`

## Gas Report

| Function | Min | Avg | Median | Max |
|---|---|---|---|---|
| `deploy` | — | — | — | 1,188,603 |
| `mint` | 24,640 | 58,419 | 71,402 | 71,426 |
| `burn` | 24,471 | 29,288 | 29,288 | 34,105 |
| `transfer` | 51,939 | 51,939 | 51,939 | 51,939 |
| `balanceOf` | 2,873 | 2,873 | 2,873 | 2,873 |
| `totalSupply` | 2,500 | 2,500 | 2,500 | 2,500 |

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
cp .env.example .env   # fill in PRIVATE_KEY, OWNER_ADDRESS, RPC_URL
forge script script/Deploy.s.sol:DeployAuroraToken \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

## Verify

```shell
forge verify-contract \
  --chain-id 11155111 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" "$OWNER_ADDRESS") \
  DEPLOYED_ADDRESS \
  src/AuroraToken.sol:AuroraToken
```

## Project Structure

```
aurora-token/
├── src/AuroraToken.sol       # Token contract
├── test/AuroraToken.t.sol    # Tests
├── script/Deploy.s.sol       # Deployment script
├── lib/                      # Dependencies (OpenZeppelin, forge-std)
├── .env.example              # Required env vars (no values)
└── README.md
```

## Dependencies

- OpenZeppelin Contracts v5.x (`@openzeppelin/contracts`)
- Foundry (forge, cast, anvil)
