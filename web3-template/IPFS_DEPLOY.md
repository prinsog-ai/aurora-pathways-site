# IPFS Deployment Guide — Aurora Pathways Web3 Template

This guide walks you through deploying the Aurora Pathways single-page website to IPFS (InterPlanetary File System) using **free tools**. Once deployed, your site will be permanently accessible via IPFS gateways and can be linked to an ENS domain or traditional DNS.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Method 1: Pinata (Easiest)](#method-1-pinata-recommended)
3. [Method 2: web3.storage](#method-2-web3storage)
4. [Method 3: IPFS Desktop + Local Node](#method-3-ipfs-desktop)
5. [Method 4: Fleek (CI/CD + ENS)](#method-4-fleek-cicd--ens)
6. [Accessing Your Deployed Site](#accessing-your-deployed-site)
7. [Custom Domain Setup (ENS / DNSLink)](#custom-domain-setup-ens--dnslink)
8. [Updating Your Site](#updating-your-site)
9. [Coinbase Commerce Configuration](#coinbase-commerce-configuration)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- The website files (`index.html` and any assets) ready in a folder
- A free account on at least one of: [Pinata](https://pinata.cloud), [web3.storage](https://web3.storage), or [Fleek](https://fleek.xyz)

---

## Method 1: Pinata (Recommended)

Pinata is the most user-friendly IPFS pinning service. Free tier includes 1 GB storage and reasonable bandwidth.

### Step 1: Create a Pinata Account

1. Go to [https://pinata.cloud](https://pinata.cloud)
2. Click **"Sign Up"** — free tier is fine
3. Verify your email and log in

### Step 2: Upload Your Site

1. In the Pinata dashboard, click **"Upload" → "Folder"**
2. Select the entire folder containing your site (e.g., `web3-template/`)
   - Make sure the folder contains `index.html` at its root
3. Name your upload something descriptive, e.g., `aurora-pathways-v1`
4. Check **"Preserve folder structure"**
5. Click **"Upload"**

### Step 3: Get Your IPFS Hash

1. After upload completes, click on your pinned file/folder in the Pinata Files list
2. Copy the **CID** (Content Identifier) — it looks like:
   ```
   QmXyZ1234abcdef5678ghijk9012lmnop3456qrst
   ```
3. Your site is now live at:
   ```
   https://gateway.pinata.cloud/ipfs/YOUR_CID/
   ```
   Or any public gateway:
   ```
   https://ipfs.io/ipfs/YOUR_CID/
   https://cloudflare-ipfs.com/ipfs/YOUR_CID/
   ```

### Step 4 (Optional): Set Up a Dedicated Gateway

Pinata offers dedicated gateways (even on free tier) for a cleaner URL:

1. In Pinata, go to **"Gateways"**
2. Create a gateway with your chosen subdomain
3. Map your CID or IPNS name to it

---

## Method 2: web3.storage

web3.storage by Protocol Labs provides 5 GB free storage through Filecoin and IPFS.

### Step 1: Install web3.storage CLI

```bash
# Requires Node.js 16+
npm install -g @web3-storage/w3cli
```

### Step 2: Authenticate

```bash
w3 login
# This opens a browser window — authorize with your GitHub or email
```

### Step 3: Create a Space

```bash
w3 space create "Aurora Pathways"
w3 space use
```

### Step 4: Upload Your Site

```bash
cd /Users/woedem/aurora-pathways-site/web3-template
w3 up .
```

The CLI will output something like:

```
⁂ Stored 1 file
⁂ https://w3s.link/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi
```

Copy the CID or URL — your site is now live.

### Step 5: Access via Gateway

```
https://w3s.link/ipfs/YOUR_CID/
https://ipfs.io/ipfs/YOUR_CID/
```

---

## Method 3: IPFS Desktop

Run your own IPFS node locally and serve the site from your machine. Best for development and testing.

### Step 1: Install IPFS Desktop

1. Download from [https://docs.ipfs.tech/install/ipfs-desktop/](https://docs.ipfs.tech/install/ipfs-desktop/)
2. Install and launch the application
3. Wait for the node to connect to the IPFS network (status bar turns green)

### Step 2: Import Your Site

1. In IPFS Desktop, click **"Files"** tab
2. Click **"Import" → "Folder"**
3. Select the `web3-template/` folder
4. Your folder appears with a CID

### Step 3: Pin to a Remote Service

Local IPFS is ephemeral — other nodes won't persist your content forever. Pin to a remote service:

1. Click the **"…"** menu on your folder
2. Select **"Set Pinning"**
3. Add a pinning service endpoint (Pinata, web3.storage, etc.)

Or configure automatic pinning in IPFS Desktop settings under **"Pinning Services"**.

### Step 4: Access

```
http://127.0.0.1:8080/ipfs/YOUR_CID/
```

---

## Method 4: Fleek (CI/CD + ENS)

Fleek provides automated IPFS deployments from Git repositories with ENS/DNSLink support.

### Step 1: Sign Up

1. Go to [https://fleek.xyz](https://fleek.xyz)
2. Sign up with GitHub

### Step 2: Connect Repository

1. Push your site to a GitHub repository:
   ```bash
   cd /Users/woedem/aurora-pathways-site/web3-template
   git init
   git add .
   git commit -m "Initial Aurora Pathways template"
   git remote add origin https://github.com/YOUR_USERNAME/aurora-pathways-site.git
   git push -u origin main
   ```

2. On Fleek, click **"Add New Site"**
3. Connect your GitHub and select the repository
4. Configure:
   - **Build command:** (leave blank — pure HTML site)
   - **Publish directory:** `.` (or the folder name)

### Step 3: Deploy

Fleek will automatically deploy on every `git push` to your main branch.

### Step 4: Custom Domain

1. In Fleek, go to your site settings → **"Domain Management"**
2. Add an ENS domain or traditional DNS domain
3. Fleek sets up DNSLink automatically

---

## Accessing Your Deployed Site

Once deployed to IPFS, your site is accessible through any **public IPFS gateway**:

| Gateway URL | Description |
|---|---|
| `https://ipfs.io/ipfs/YOUR_CID/` | Protocol Labs official gateway |
| `https://cloudflare-ipfs.com/ipfs/YOUR_CID/` | Cloudflare gateway (fast) |
| `https://gateway.pinata.cloud/ipfs/YOUR_CID/` | Pinata gateway (if pinned there) |
| `https://w3s.link/ipfs/YOUR_CID/` | web3.storage gateway |
| `https://dweb.link/ipfs/YOUR_CID/` | Another popular gateway |
| `https://cf-ipfs.com/ipfs/YOUR_CID/` | Cloudflare IPFS |

> **Important:** Replace `YOUR_CID` with the actual content identifier from your upload.

**First load may be slow** — IPFS content propagates through the network. Subsequent loads will be fast as gateways cache the content.

---

## Custom Domain Setup (ENS / DNSLink)

### ENS Domain (e.g., `aurorapathways.eth`)

If you own an ENS domain:

1. Go to [https://app.ens.domains](https://app.ens.domains)
2. Click on your domain → **"Records"**
3. Add a **Content Hash** record:
   - Paste your IPFS CID (e.g., `ipfs://YOUR_CID`)
   - Or use IPNS: `ipns://YOUR_IPNS_KEY`
4. Save and confirm the transaction

Now `aurorapathways.eth` will resolve to your IPFS site when accessed through:
```
https://aurorapathways.eth.limo/
https://aurorapathways.eth.link/
```

### Traditional DNS + DNSLink

1. Add a TXT record to your DNS configuration:
   ```
   Name: _dnslink.yourdomain.com
   Value: dnslink=/ipfs/YOUR_CID
   TTL: 3600
   ```
2. Your domain will resolve via any IPFS gateway:
   ```
   https://ipfs.io/ipns/yourdomain.com/
   ```

---

## Updating Your Site

IPFS content is immutable — every change produces a new CID. To update your live site:

### Option A: Update DNSLink (Recommended)
1. Upload the new version to IPFS (get a new CID)
2. Update your DNSLink TXT record to point to the new CID:
   ```
   dnslink=/ipfs/NEW_CID
   ```
3. DNS propagation takes a few minutes to a few hours

### Option B: Use IPNS (Mutable Pointer)
1. Generate an IPNS key:
   ```bash
   ipfs key gen my-site-key
   ```
2. Publish to IPNS:
   ```bash
   ipfs name publish --key=my-site-key /ipfs/YOUR_CID
   ```
3. Update your ENS content hash to point to your IPNS key:
   ```
   ipns://k51qzi5uqu5d...
   ```
4. Re-publish whenever you update the site:
   ```bash
   ipfs add -r updated-site/
   ipfs name publish --key=my-site-key /ipfs/NEW_CID
   ```

### Option C: Fleek Auto-Deploy
If using Fleek, just push to Git — Fleek automatically redeploys and updates IPNS.

---

## Coinbase Commerce Configuration

The template includes placeholder Coinbase Commerce integration. To enable real crypto payments:

### Step 1: Create a Coinbase Commerce Account

1. Go to [https://commerce.coinbase.com](https://commerce.coinbase.com)
2. Sign up with your Coinbase account
3. Complete business verification (KYC)

### Step 2: Create Charge Links

1. In Coinbase Commerce dashboard, go to **"Charges"**
2. Click **"Create a Charge"**
3. Set the charge details (amount, currency, description)
4. After creating, you'll get a hosted checkout URL like:
   ```
   https://commerce.coinbase.com/checkout/abc123de-f456-7890-abcd-ef1234567890
   ```

### Step 3: Update the Template

Open `index.html` and find the `PAYMENT_LINKS` object (around line 620):

```javascript
const PAYMENT_LINKS = {
  'Starter': 'https://commerce.coinbase.com/checkout/YOUR_CHARGE_ID_STARTER',
  'Professional': 'https://commerce.coinbase.com/checkout/YOUR_CHARGE_ID_PRO',
};
```

Replace the placeholder URLs with your actual Coinbase Commerce checkout URLs.

### Step 4: Test Payments

1. Click "Pay with Crypto" on the Starter or Professional plan
2. The Coinbase Commerce hosted checkout opens in a new tab
3. Test with a small amount on testnet first
4. Verify the payment appears in your Coinbase Commerce dashboard

### Accepted Cryptocurrencies (via Coinbase Commerce)

- Ethereum (ETH)
- USD Coin (USDC)
- Bitcoin (BTC)
- Litecoin (LTC)
- Dogecoin (DOGE)
- Dai (DAI)
- And 100+ more depending on your Coinbase Commerce settings

---

## Troubleshooting

### "No wallet detected" error
- Install [MetaMask](https://metamask.io) browser extension
- Or use a Web3-compatible browser (Brave, Opera)
- On mobile, open in MetaMask's built-in browser

### IPFS site won't load
- Wait a few minutes — first load can be slow as gateways discover content
- Try a different gateway
- Verify your CID is correct
- Check that your pinning service shows the file as "pinned"

### ENS domain not resolving
- Ensure the transaction confirmed on-chain (check Etherscan)
- Try adding `.limo` or `.link` suffix: `yourname.eth.limo`
- Wait up to 5 minutes for DNS propagation
- Verify the content hash is in the correct format: `ipfs://CID`

### CSS/Fonts not loading on IPFS
- All fonts are loaded via CDN in this template — no local font files needed
- If you add local assets, ensure paths are **relative** (no leading `/`)
- Use `./images/logo.png` not `/images/logo.png`

### Coinbase Commerce checkout not opening
- Verify the charge ID in `PAYMENT_LINKS` is not the placeholder
- Check that the charge is active in your Coinbase Commerce dashboard
- Ensure no ad-blocker is interfering with the popup

---

## Quick Deploy Checklist

- [ ] Upload `index.html` (and folder) to Pinata or web3.storage
- [ ] Copy the CID from the upload result
- [ ] Test the gateway URL: `https://ipfs.io/ipfs/YOUR_CID/`
- [ ] Test wallet connection (MetaMask)
- [ ] Replace Coinbase Commerce placeholder charge IDs with real ones
- [ ] Test a crypto payment (small amount on testnet)
- [ ] (Optional) Set up ENS domain with content hash record
- [ ] (Optional) Configure Fleek for automatic deployments
- [ ] Share your IPFS gateway URL or ENS domain

---

## Resources

- [IPFS Documentation](https://docs.ipfs.tech)
- [Pinata Docs](https://docs.pinata.cloud)
- [web3.storage Docs](https://web3.storage/docs)
- [Fleek Docs](https://docs.fleek.xyz)
- [ENS Documentation](https://docs.ens.domains)
- [Coinbase Commerce API](https://docs.cloud.coinbase.com/commerce/docs)
- [ethers.js Documentation](https://docs.ethers.org)

---

**Deployed with ✦ Aurora Pathways — aurorapathways.eth**
