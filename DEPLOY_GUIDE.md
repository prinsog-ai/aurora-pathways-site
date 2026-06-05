# Aurora Pathways — Live Deployment Guide

## Option 1: IPFS (Free, Decentralized, Most On-Brand)

### Step 1: Install IPFS
```bash
# macOS
brew install ipfs

# Or use IPFS Desktop: https://docs.ipfs.tech/install/ipfs-desktop/
```

### Step 2: Add your site to IPFS
```bash
cd /Users/woedem/aurora-pathways-site
ipfs add -r index.html
# Copy the CID (e.g., QmXyZ...)
```

### Step 3: Pin it (so it stays online)
```bash
# Free pinning services:
# Option A: Pinata (pinata.cloud) — free tier: 1GB
# Option B: web3.storage — free tier: 5GB
# Option C: Filebase (filebase.com) — free tier: 5GB
```

### Step 4: Access your site
```
https://ipfs.io/ipfs/YOUR_CID
https://gateway.pinata.cloud/ipfs/YOUR_CID
```

### Step 5: Add a domain (optional)
```bash
# Point yourdomain.com DNS to an IPFS gateway, or
# Use Fleek.co for automatic IPFS + domain management
```

---

## Option 2: Netlify (Free, 1-Click, Custom Domain)

### One command deploy:
```bash
cd /Users/woedem/aurora-pathways-site
npx netlify-cli deploy --prod --dir=.
```

Or drag and drop the `index.html` to: https://app.netlify.com/drop

---

## Option 3: Surge.sh (Free, Instant)

```bash
npm install -g surge
cd /Users/woedem/aurora-pathways-site
surge . aurorapathways.surge.sh
```

This gives you: https://aurorapathways.surge.sh

---

## Option 4: Vercel (Free, Custom Domain Support)

```bash
cd /Users/woedem/aurora-pathways-site
npx vercel --prod
```

---

## Recommended: Netlify for Now

You own the files. All four options are free. Netlify is the simplest for a professional feel with a custom domain later.
