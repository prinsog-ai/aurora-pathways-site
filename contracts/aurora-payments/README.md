# AuroraPayments

Multi-chain stablecoin payment splitter for Aurora Pathways. Accepts USDC, USDT, DAI on any EVM chain and splits payments to pre-configured recipients.

## Contract

**AuroraPayments** (`src/AuroraPayments.sol`) — inherits OpenZeppelin `Ownable` + `ReentrancyGuard`.

- **Payment Splitting**: Configurable recipient shares in basis points (must sum to 10,000 = 100%)
- **Multi-Token Support**: Add any ERC-20 token as a supported payment method
- **Distribution**: Anyone can trigger distribution of accumulated token balance
- **Revenue Tracking**: Per-token total revenue and per-recipient earnings tracked on-chain
- **Reentrancy Protection**: Distribution function protected against reentrancy

## Gas Report

| Function | Min | Avg | Median | Max |
|---|---|---|---|---|
| `deploy` | — | — | — | 1,397,916 |
| `setRecipients` | 56,037 | 154,966 | 163,211 | 163,211 |
| `distribute` | 29,477 | 96,026 | 79,223 | 164,723 |
| `addSupportedToken` | 24,271 | 46,767 | 48,390 | 48,390 |
| `removeSupportedToken` | 25,484 | 25,484 | 25,484 | 25,484 |

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
forge create --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  src/AuroraPayments.sol:AuroraPayments \
  --constructor-args $OWNER_ADDRESS
```

## Verify

```shell
forge verify-contract \
  --chain-id 11155111 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" "$OWNER_ADDRESS") \
  DEPLOYED_ADDRESS \
  src/AuroraPayments.sol:AuroraPayments
```

## Usage Flow

1. **Deploy** with the agency's multisig as owner
2. **Add supported tokens** (USDC, USDT, DAI addresses per chain)
3. **Set recipients** with share percentages (must total 100%)
4. **Clients send payments** directly to the contract address
5. **Anyone calls `distribute()`** to split accumulated tokens to recipients

## Project Structure

```
aurora-payments/
├── src/AuroraPayments.sol       # Payment splitter contract
├── test/AuroraPayments.t.sol    # Tests (12 tests)
├── lib/                         # Dependencies (OpenZeppelin, forge-std)
├── .env.example                 # Required env vars (no values)
└── README.md
```

## Dependencies

- OpenZeppelin Contracts v5.x (`@openzeppelin/contracts`)
- Foundry (forge, cast, anvil)