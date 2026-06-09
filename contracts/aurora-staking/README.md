# Aurora Staking Contract

ERC-20 staking contract for the AURA token. Stake tokens to earn rewards over time.

## Features

- **Deposit/Withdraw** — stake and unstake AURA tokens at any time
- **Per-second rewards** — rewards accrue every second based on share of total staked
- **Configurable reward rate** — owner can adjust tokens per second
- **Claim rewards** — withdraw accrued rewards without unstaking
- **Compound rewards** — restake rewards for compounding returns
- **Minimum stake** — configurable minimum deposit amount
- **Reward pool capping** — never pays out more than funded reward pool
- **ReentrancyGuard** — all token functions protected
- **Accidental token recovery** — recover non-staking tokens sent by mistake

## Build

```bash
source ~/.zshenv
forge build
```

## Test

```bash
source ~/.zshenv
forge test -vvv
```

## Gas Report

```bash
source ~/.zshenv
forge test --gas-report
```

## Deploy

### Local (Anvil)

```bash
source ~/.zshenv
anvil &
forge script script/Deploy.s.sol:DeployAuroraStaking \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvvv
```

### Testnet (Polygon Amoy)

```bash
source ~/.zshenv
cp .env.example .env
# Fill in PRIVATE_KEY, OWNER_ADDRESS, STAKING_TOKEN_ADDRESS

CHAIN=amoy forge script script/Deploy.s.sol:DeployAuroraStaking \
  --rpc-url $AMOY_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

## Contract Interaction (cast)

```bash
# Stake tokens (must approve first)
cast send $AURA_TOKEN "approve(address,uint256)" $STAKING_CONTRACT 1000000000000000000000 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

cast send $STAKING_CONTRACT "stake(uint256)" 1000000000000000000000 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Check pending rewards
cast call $STAKING_CONTRACT "pendingReward(address)(uint256)" $YOUR_ADDRESS --rpc-url $RPC_URL

# Claim rewards
cast send $STAKING_CONTRACT "claimReward()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Compound rewards
cast send $STAKING_CONTRACT "compoundReward()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Withdraw
cast send $STAKING_CONTRACT "withdraw(uint256)" 500000000000000000000 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## Environment Variables

See `.env.example` for required and optional configuration.
