#!/usr/bin/env bash
# Deploy Valence Carbon Credit system
# Usage: CHAIN=polygon ./deploy.sh
set -euo pipefail

cd "$(dirname "$0")"

# Load .env if it exists
[ -f .env ] && source .env

: "${PRIVATE_KEY:?Set PRIVATE_KEY}"
: "${OWNER_ADDRESS:?Set OWNER_ADDRESS}"
: "${CHAIN:=polygon}"

echo "Deploying Valence Carbon Credit to: $CHAIN"
echo "Owner: $OWNER_ADDRESS"
echo ""

~/.foundry/bin/forge script script/Deploy.s.sol:DeployValence \
  --rpc-url "${CHAIN}_RPC_URL" \
  --broadcast \
  -vvv

echo ""
echo "Done! Copy the addresses above into your .env or config."
