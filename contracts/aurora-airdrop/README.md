# Aurora Airdrop (Merkle Distributor)

Gas-efficient ERC-20 airdrop using Merkle proofs. Each eligible address can claim their allocated tokens by providing a Merkle proof.

## Features

- **Merkle verification** — gas-efficient, no need to store all recipients on-chain
- **Per-address allocation** — each leaf = keccak256(address, amount)
- **Claim once** — each address can only claim once
- **Configurable deadline** — optional claim window with owner recovery
- **New rounds** — owner can update Merkle root for subsequent airdrops
- **ReentrancyGuard** — claim function protected

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

```bash
source ~/.zshenv
cp .env.example .env
# Fill in required vars

CHAIN=amoy forge script script/Deploy.s.sol:DeployAuroraAirdrop \
  --rpc-url $AMOY_RPC_URL \
  --broadcast --verify -vvvv
```

## Generating Merkle Trees

Use a script or tool to generate the Merkle tree. Each leaf is:
```
keccak256(abi.encodePacked(address, uint256 amount))
```

Example in JavaScript with `@openzeppelin/merkle-tree`:
```js
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

const tree = StandardMerkleTree.of(
  [
    ["0xAlice...", "1000000000000000000000"],
    ["0xBob...", "2000000000000000000000"],
  ],
  ["address", "uint256"]
);

console.log("Merkle Root:", tree.root);
console.log("Alice proof:", tree.getProof(0));
```

## Environment Variables

See `.env.example` for required configuration.
