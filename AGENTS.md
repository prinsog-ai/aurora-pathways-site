# AGENTS.md — Aurora Pathways

Static marketing site for Aurora Pathways, a Web3 consulting agency.  
Deployed to `aurorapathways.xyz` via Netlify (no build step — raw HTML/CSS/JS).

## Tech stack

- **HTML/CSS/JS** — no framework, no bundler, no preprocessor
- **CSS** — all inline `<style>` blocks using CSS custom properties (`:root` vars)
- **JS** — all inline `<script>` blocks, IntersectionObserver for animations
- **Font** — Inter (Google Fonts CDN)
- **External** — Umami analytics, Calendly widget, CoinGecko API, Netlify Forms, ethers.js (wallet pages)
- **Contracts** — Foundry/Solidity in `contracts/`
- **IPFS** — Pinata for `.blockchain` domain deployment

## Commands

```bash
# Deploy to Netlify (from repo root)
~/.hermes/node/bin/netlify deploy --prod --dir=.

# Run contract tests
~/.foundry/bin/forge test --root contracts/tasklync

# Upload to IPFS
bash deploy-ipfs.sh
```

## Where to look

| What | File |
|------|------|
| Site structure & routes | [docs/structure.md](docs/structure.md) |
| Reusable components & CSS classes | [docs/components.md](docs/components.md) |
| JS behaviors & selector dependencies | [docs/js-behavior.md](docs/js-behavior.md) |
| Architecture diagram | [docs/architecture.md](docs/architecture.md) |
| Main page section map | [docs/index-map.md](docs/index-map.md) |

## Critical constraints

- **All CSS/JS is inline** — no separate files to edit
- **Do not rename** `#cursorGlow`, `#auroraBg`, `#navbar`, `.reveal`, `.counter[data-target]` — JS depends on them
- **Portfolio pages** all link to `../index.html#portfolio` — keep this consistent
- **Dark theme** — `--bg:#0a0a0f`, `--accent:#7c5cfc`, `--accent2:#4ec9b0`, `--accent3:#ff6b9d`
- **No fake social proof** — verifiable metrics only
- **test-count.json** is polled every 30s by the landing page JS
