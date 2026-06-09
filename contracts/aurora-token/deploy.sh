#!/usr/bin/env bash
# ============================================================
# Aurora Pathways — Multi-Chain Deploy & Verify
# ============================================================
# Usage:
#   source ~/.zshenv
#   ./deploy.sh polygon          # Deploy AuroraToken to Polygon mainnet
#   ./deploy.sh amoy             # Deploy to Polygon Amoy testnet
#   ./deploy.sh base             # Deploy to Base mainnet
#   ./deploy.sh base-sepolia     # Deploy to Base Sepolia testnet
#   ./deploy.sh arbitrum         # Deploy to Arbitrum mainnet
#   ./deploy.sh arbitrum-sepolia # Deploy to Arbitrum Sepolia testnet
#   ./deploy.sh anvil            # Deploy to local Anvil node
#
# Requirements: Foundry (forge, cast), .env with PRIVATE_KEY + OWNER_ADDRESS
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAIN="${1:-anvil}"
ENV_FILE="$SCRIPT_DIR/.env"

# Load .env if it exists
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
else
  echo "⚠️  No .env file found at $ENV_FILE"
  echo "   Copy .env.example to .env and fill in your values."
  exit 1
fi

# Validate required vars
if [ -z "${PRIVATE_KEY:-}" ] || [ -z "${OWNER_ADDRESS:-}" ]; then
  echo "❌ PRIVATE_KEY and OWNER_ADDRESS must be set in .env"
  exit 1
fi

echo "=== AuroraToken Multi-Chain Deploy ==="
echo "Chain: $CHAIN"
echo ""

# --- Build ---
echo "📦 Compiling..."
forge build --via-ir
echo ""

# --- Test ---
echo "🧪 Running tests..."
forge test -v
echo ""

# --- Deploy ---
echo "🚀 Deploying to $CHAIN..."
CHAIN=$CHAIN forge script script/MultiChainDeploy.s.sol:MultiChainDeploy \
  --rpc-url "$(get_rpc "$CHAIN")" \
  --broadcast \
  --verify \
  -vvvv

echo ""
echo "✅ Deployment complete!"

# --- Helper: get RPC URL for chain ---
get_rpc() {
  case "$1" in
    polygon)         echo "${POLYGON_RPC_URL:-https://polygon-rpc.com}" ;;
    amoy)            echo "${AMOY_RPC_URL:-https://rpc-amoy.polygon.technology}" ;;
    base)            echo "${BASE_RPC_URL:-https://mainnet.base.org}" ;;
    base-sepolia)    echo "${BASE_SEPOLIA_RPC_URL:-https://sepolia.base.org}" ;;
    arbitrum)        echo "${ARBITRUM_RPC_URL:-https://arb1.arbitrum.io/rpc}" ;;
    arbitrum-sepolia) echo "${ARBITRUM_SEPOLIA_RPC_URL:-https://sepolia-rollup.arbitrum.io/rpc}" ;;
    anvil)           echo "${ANVIL_RPC_URL:-http://localhost:8545}" ;;
    *)               echo "Unknown chain: $1"; exit 1 ;;
  esac
}