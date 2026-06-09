#!/usr/bin/env python3
"""Upload 4 landing pages to Pinata IPFS."""
import subprocess, json, sys

JWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySW5mb3JtYXRpb24iOnsiaWQiOiIxNjY0Y2Y5Yy03YTc0LTRkM2UtODcyMS0xM2YxZDQyNWEzMWYiLCJlbWFpbCI6ImF1cm9yYXBhdGh3YXlzQHlhaG9vLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJwaW5fcG9saWN5Ijp7InJlZ2lvbnMiOlt7ImRlc2lyZWRSZXBsaWNhdGlvbkNvdW50IjoxLCJpZCI6IkZSQTEifSx7ImRlc2lyZWRSZXBsaWNhdGlvbkNvdW50IjoxLCJpZCI6Ik5ZQzEifV0sInZlcnNpb24iOjF9LCJtZmFfZW5hYmxlZCI6ZmFsc2UsInN0YXR1cyI6IkFDVElWRSJ9LCJhdXRoZW50aWNhdGlvblR5cGUiOiJzY29wZWRLZXkiLCJzY29wZWRLZXlLZXkiOiIyN2FlYWNiZjI0N2MyOWNhN2E3OSIsInNjb3BlZEtleVNlY3JldCI6ImJjNTcyYjE1NzgzOTliMWQ2NWY1ODNhN2EwYjZkOGI4Y2Y3NWE5YTMzNTY2M2QyZDA3OGZkYjI5MDdkYzFmZGYiLCJleHAiOjE4MTIyMjM5MDN9.1YtPvKvif8SomnO07s3bE-1J_qCvsrTq_yG1I9uHiBY"

BASE = "/Users/woedem/aurora-pathways-site"
products = ["creatorly", "forekast", "tripdrop"]

for product in products:
    path = f"{BASE}/landing/{product}/index.html"
    print(f"📤 Uploading {product}...")
    result = subprocess.run([
        "curl", "-s", "-X", "POST",
        "https://api.pinata.cloud/pinning/pinFileToIPFS",
        "-H", f"Authorization: Bearer {JWT}",
        "-F", f"file=@{path}",
        "-F", f'pinataMetadata={{"name":"{product}-landing"}}'
    ], capture_output=True, text=True, timeout=30)
    
    try:
        data = json.loads(result.stdout)
        cid = data.get("IpfsHash", "")
        if cid:
            print(f"  ✅ {product} → {cid}")
            print(f"  🌐 https://{cid}.ipfs.dweb.link")
            print(f"  📋 UD: Set {product}.blockchain → ipfs://{cid}")
        else:
            print(f"  ❌ Failed: {result.stdout}")
    except Exception as e:
        print(f"  ❌ Error: {e} | {result.stdout[:200]}")
    print()
