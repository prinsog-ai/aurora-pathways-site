# Aurora Multi-Token (ERC-1155)

ERC-1155 multi-token contract for the Aurora Pathways ecosystem. Supports membership tiers, gaming items, and multi-asset collections with a single contract.

## Features

- **Multiple token types** — create unlimited token IDs, each with its own max supply, price, and metadata URI
- **Membership tiers** — Bronze, Silver, Gold etc. as different token IDs
- **Gaming items** — swords, shields, potions with configurable supply limits
- **Per-token URI** — each token ID has its own metadata URI (ERC1155URIStorage)
- **Supply tracking** — total supply per token ID and globally (ERC1155Supply)
- **Burnable** — token holders can burn their own tokens
- **Pausable** — owner can pause all transfers and mints
- **Batch operations** — mint and transfer multiple token types in one transaction
- **Owner-only minting** — free mints for team, marketing, airdrops
- **ReentrancyGuard** — all payable functions protected

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
forge script script/Deploy.s.sol:DeployAuroraMultiToken \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvvv
```

### Testnet (Polygon Amoy)

```bash
source ~/.zshenv
cp .env.example .env
# Fill in PRIVATE_KEY and OWNER_ADDRESS

CHAIN=amoy forge script script/Deploy.s.sol:DeployAuroraMultiToken \
  --rpc-url $AMOY_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

### Mainnet (Polygon PoS)

```bash
CHAIN=polygon forge script script/Deploy.s.sol:DeployAuroraMultiToken \
  --rpc-url $POLYGON_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

## Contract Interaction (cast)

After deployment, interact with the contract:

```bash
# Create a new token type (owner only)
cast send $CONTRACT "createTokenType(uint256,uint256,uint256,string)" \
  1 1000 10000000000000000 "ipfs://token1.json" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Mint tokens (payable)
cast send $CONTRACT "mint(address,uint256,uint256)" \
  $YOUR_ADDRESS 1 5 \
  --value 50000000000000000 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Check balance
cast call $CONTRACT "balanceOf(address,uint256)(uint256)" $YOUR_ADDRESS 1 --rpc-url $RPC_URL

# Check total supply
cast call $CONTRACT "totalSupply(uint256)(uint256)" 1 --rpc-url $RPC_URL
```

## Environment Variables

See `.env.example` for required and optional configuration.

## Security

- All payable functions use `ReentrancyGuard`
- Owner-only functions use OpenZeppelin `Ownable`
- Max supply enforcement per token type
- ERC-1155 standard compliance with `safeTransferFrom` and `safeBatchTransferFrom`
