# Aurora Multi-Sig Factory

Factory contract for deploying custom multi-signature wallets for Aurora Pathways clients.

## Features

- **Factory pattern** — deploy new multi-sig wallets on demand
- **Configurable signers** — any number of authorized signers
- **Configurable threshold** — N-of-M confirmation requirement
- **Transaction lifecycle** — submit → confirm → execute
- **Revoke confirmations** — signers can change their mind
- **ETH and ERC-20 support** — execute arbitrary contract calls
- **Owner management** — update signers and threshold
- **Transaction tracking** — per-signer transaction counts

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

## Deploy

### Local (Anvil)

```bash
source ~/.zshenv
anvil &
forge script script/Deploy.s.sol:DeployMultiSigFactory \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvvv
```

### Testnet (Polygon Amoy)

```bash
source ~/.zshenv
cp .env.example .env
# Fill in PRIVATE_KEY and OWNER_ADDRESS

CHAIN=amoy forge script script/Deploy.s.sol:DeployMultiSigFactory \
  --rpc-url $AMOY_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

## Usage

### Deploy a multi-sig via factory

```bash
cast send $FACTORY "deployMultiSig(address[],uint256,address)" \
  "[$SIGNER1,$SIGNER2,$SIGNER3]" 2 $MS_OWNER \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Submit a transaction

```bash
cast send $WALLET "submitTransaction(address,uint256,bytes)" \
  $RECIPIENT 1000000000000000000 0x \
  --rpc-url $RPC_URL --private-key $SIGNER_KEY
```

### Confirm and execute

```bash
cast send $WALLET "confirmTransaction(uint256)" 0 \
  --rpc-url $RPC_URL --private-key $SIGNER_KEY

cast send $WALLET "executeTransaction(uint256)" 0 \
  --rpc-url $RPC_URL --private-key $SIGNER_KEY
```

## Environment Variables

See `.env.example` for required configuration.
