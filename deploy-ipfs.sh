#!/usr/bin/env bash
# ============================================================
# IPFS Deploy — Upload landing pages to Pinata (JWT auth)
# ============================================================
# Usage:
#   export PINATA_JWT="your_jwt_token"
#   ./deploy-ipfs.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANDING_DIR="$SCRIPT_DIR/landing"

if [ -z "${PINATA_JWT:-}" ]; then
  echo "❌ Set PINATA_JWT"
  exit 1
fi

echo "=== IPFS Deploy — Aurora Pathways Protocols ==="
echo ""

for product in tasklync creatorly forekast tripdrop; do
  PAGE="$LANDING_DIR/$product/index.html"
  if [ ! -f "$PAGE" ]; then
    echo "⚠️  Skipping $product — page not found"
    continue
  fi

  echo "📤 Uploading $product..."

  RESPONSE=$(curl -s -X POST "https://api.pinata.cloud/pinning/pinFileToIPFS" \
    -H "Authorization: Bearer $PINATA_JWT" \
    -F "file=@$PAGE" \
    -F "pinataMetadata={\"name\":\"$product-landing\"}")

  CID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['IpfsHash'])" 2>/dev/null)

  if [ -n "$CID" ]; then
    echo "  ✅ $product → $CID"
    echo "  🌐 https://$CID.ipfs.dweb.link"
    echo "  📋 UD: Set $product.blockchain → ipfs://$CID"
    echo ""
  else
    echo "  ❌ Upload failed for $product"
    echo "  $RESPONSE"
    echo ""
  fi
done

echo "=== Done ==="
echo ""
echo "Next: Go to unstoppabledomains.com → My Domains → each domain"
echo "Set DNS record: Content Hash = ipfs://CID (from above)"
