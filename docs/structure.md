# File & Route Map

## URL → HTML File Mapping

| URL Path | HTML File | Description |
|---|---|---|
| `/` | `index.html` | Main site (1777 lines). All CSS/JS inline. |
| `/pitch-deck.html` | `pitch-deck.html` | Investor deck (329 lines). Scroll-snap slides. |
| `/portfolio/<name>.html` | `portfolio/<name>.html` | 18 case-study pages (6 protocol + 12 industry demos). |
| `/portfolio/ipfs-deploy.html` | `portfolio/ipfs-deploy.html` | IPFS deployment demo page. |
| `/landing/tasklync/` | `landing/tasklync/index.html` | Tasklync DAO landing page. |
| `/landing/tasklync/blockchain/` | `landing/tasklync/blockchain/index.html` | Tasklync blockchain info subpage (ethers.js v5 wallet connect). |
| `/landing/tasklync/dapp/` | `landing/tasklync/dapp/index.html` | Tasklync escrow dApp (ethers.js v6, Polygon Amoy). |
| `/landing/pledgly/` | `landing/pledgly/index.html` | Pledgly DAO landing page. |
| `/landing/pledgly/blockchain/` | `landing/pledgly/blockchain/index.html` | Pledgly blockchain subpage. |
| `/landing/forekast/` | `landing/forekast/index.html` | Forekast DAO landing page. |
| `/landing/forekast/blockchain/` | `landing/forekast/blockchain/index.html` | Forekast blockchain subpage. |
| `/landing/ridep2p/` | `landing/ridep2p/index.html` | Ridep2p DAO landing page. |
| `/landing/ridep2p/blockchain/` | `landing/ridep2p/blockchain/index.html` | Ridep2p blockchain subpage. |
| `/landing/creatorly/` | `landing/creatorly/index.html` | Creatorly landing page. |
| `/landing/tripdrop/` | `landing/tripdrop/index.html` | TripDrop landing page. |
| `/blog/web3-website-2026.html` | `blog/web3-website-2026.html` | Blog article. |
| `/blog/crypto-payments-guide.html` | `blog/crypto-payments-guide.html` | Blog article. |
| `/blog/nft-business-applications.html` | `blog/nft-business-applications.html` | Blog article. |
| `/tools/web3-quiz.html` | `tools/web3-quiz.html` | Interactive Web3 readiness quiz. |
| `/test-count.json` | `test-count.json` | Polled by index.html JS for live test count. |

## CSS Locations

- **index.html** — All CSS in a single `<style>` block (lines 10–819). No external CSS files.
- **pitch-deck.html** — Inline `<style>` block. Separate design system (scroll-snap slides).
- **portfolio/*.html** — Each has its own inline `<style>`. Share same CSS custom properties but self-contained.
- **landing/*/index.html** — Inline `<style>`. Aurora-bg via CSS gradient (not parallax div).
- **landing/*/blockchain/index.html** — Inline `<style>`. Simpler layout, wallet-focused.
- **landing/tasklync/dapp/index.html** — Inline `<style>`. Full dApp UI styles.
- **blog/*.html** — Inline `<style>`. Article layout with aurora-bg CSS gradient.
- **tools/web3-quiz.html** — Inline `<style>`. Quiz container layout.

## JS Locations

- **index.html** — Inline `<script>` block (lines 1637–1774). See [js-behavior.md](js-behavior.md).
- **pitch-deck.html** — Inline `<script>`. Slide navigation via IntersectionObserver + nav dots.
- **landing/tasklync/dapp/index.html** — Inline `<script>` with ethers.js v6 CDN. Full escrow dApp logic.
- **landing/*/blockchain/index.html** — Inline `<script>` with ethers.js v5 CDN. Wallet connect only.
- **landing/*/index.html** — Minimal inline JS (scroll-reveal only).
- **tools/web3-quiz.html** — Inline `<script>`. Quiz state machine.
- **blog/*.html** — No JS.

## External Dependencies

| Dependency | Loaded By | Purpose |
|---|---|---|
| Google Fonts (Inter) | All pages via `@import` or `<link>` | Typography |
| Umami Analytics | `index.html` line 9 (`<script defer>`) | Page view tracking |
| Calendly Widget | `index.html` line 1635 (`<script async>`) | Booking embed |
| CoinGecko API | `index.html` JS `fetchPrices()` | Crypto price ticker |
| ethers.js v6 CDN | `landing/tasklync/dapp/index.html` | dApp wallet + contract calls |
| ethers.js v5 CDN | `landing/*/blockchain/index.html` (×4) | Wallet connect on blockchain pages |

## Key Static Files

- `test-count.json` — `{"tests": 174, "passed": 174, "failed": 0, ...}`. Polled by index.html every 30s.
- `contracts/` — Solidity projects (Foundry). Not served to browser.
- `.netlify/netlify.toml` — Netlify deploy config.
