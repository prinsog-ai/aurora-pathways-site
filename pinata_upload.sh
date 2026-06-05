#!/bin/bash
# Pinata IPFS Upload Script (reads JWT from file)
# Step 1: echo "YOUR_JWT" > /tmp/jwt.txt
# Step 2: bash /Users/woedem/aurora-pathways-site/pinata_upload.sh

JWT_FILE="/tmp/jwt.txt"
FILE="/Users/woedem/aurora-pathways-site/index.html"

if [ ! -f "$JWT_FILE" ]; then
    echo "ERROR: JWT file not found at $JWT_FILE"
    echo "Run this first: echo 'YOUR_FULL_JWT' > /tmp/jwt.txt"
    exit 1
fi

JWT=$(cat "$JWT_FILE" | tr -d '\n\r')

echo "JWT length: ${#JWT}"
echo "Uploading index.html to Pinata..."

RESPONSE=$(curl -s -X POST "https://api.pinata.cloud/pinning/pinFileToIPFS" \
  -H "Authorization: Bearer *** \
  -F "file=@$FILE" \
  -F 'pinataMetadata={"name": "aurora-pathways-index.html"}')

echo "$RESPONSE"

CID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('IpfsHash',''))" 2>/dev/null)

if [ -n "$CID" ]; then
    echo ""
    echo "=========================================="
    echo "  CID: $CID"
    echo "  Gateway: https://gateway.pinata.cloud/ipfs/$CID"
    echo "=========================================="
    echo ""
    echo "Now update aurorapathways.blockchain on UD with this CID"
fi
