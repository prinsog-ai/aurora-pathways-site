# Architecture Diagram

## Request Flow: User → Site → Integrations

```mermaid
flowchart TD
    User["👤 User / Browser"]
    DNS["🌐 DNS<br/>aurorapathways.xyz"]
    CDN["☁️ Netlify CDN<br/>Static hosting"]
    MainSite["📄 index.html<br/>1777-line SPA"]
    Portfolio["📂 portfolio/*.html<br/>18 case studies"]
    Landing["📂 landing/*/index.html<br/>DAO landing pages"]
    Dapp["📂 landing/tasklync/dapp/<br/>Escrow dApp"]
    Blog["📂 blog/*.html<br/>3 articles"]
    Quiz["📂 tools/web3-quiz.html"]
    Pitch["📄 pitch-deck.html"]

    Umami["📊 Umami Analytics<br/>cloud.umami.is"]
    Calendly["📅 Calendly Widget<br/>calendly.com/prinsog/30min"]
    CoinGecko["💰 CoinGecko API<br/>Live crypto prices"]
    NetlifyForms["📮 Netlify Forms<br/>consultation form"]
    EthersV6["⛓️ ethers.js v6<br/>Polygon Amoy escrow"]
    EthersV5["⛓️ ethers.js v5<br/>Wallet connect"]
    Pinata["📌 Pinata IPFS<br/>.blockchain domains"]
    TestJSON["📋 /test-count.json<br/>Polled every 30s"]
    GoogleFonts["🔤 Google Fonts<br/>Inter typeface"]

    User --> DNS
    DNS --> CDN
    CDN --> MainSite
    CDN --> Portfolio
    CDN --> Landing
    CDN --> Dapp
    CDN --> Blog
    CDN --> Quiz
    CDN --> Pitch
    CDN --> TestJSON

    MainSite --> Umami
    MainSite --> Calendly
    MainSite --> CoinGecko
    MainSite --> NetlifyForms
    MainSite --> GoogleFonts
    MainSite --> TestJSON

    Dapp --> EthersV6
    Landing --> EthersV5
    Landing --> Pinata

    Portfolio --> GoogleFonts
    Blog --> GoogleFonts
    Quiz --> GoogleFonts
    Pitch --> GoogleFonts
```

## Key Integration Details

- **Netlify Forms:** Form name `consultation` with honeypot `bot-field`. POST handled by Netlify automatically.
- **Calendly:** Inline widget loaded async. URL: `https://calendly.com/prinsog/30min`.
- **CoinGecko:** Free-tier REST API. Polled every 60s. Rate limits apply.
- **Umami:** Script tag with `data-website-id` and `data-domains` constraint to `aurorapathways.xyz`.
- **ethers.js v6:** Used in Tasklync dApp for full escrow interaction on Polygon Amoy testnet.
- **ethers.js v5:** Used on blockchain subpages for MetaMask wallet connect only (no contract calls).
- **Pinata IPFS:** Landing pages deployed to `.blockchain` domains via Pinata. Dual presence with `.xyz` on Netlify.
