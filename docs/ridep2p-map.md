# Ridep2p Landing Page Map

**File:** `landing/ridep2p/index.html`
**URL:** `/landing/ridep2p/`
**Title:** Ridep2p — Decentralized Ride Protocol

## Section Flow

```mermaid
flowchart TD
    Nav["Nav Bar<br/>Logo + Get in Touch CTA"]
    Hero["Hero Section<br/>Badge: Built by Aurora Pathways<br/>Title + Description<br/>Stats: 0% fee, P2P, On-chain escrow<br/>CTA buttons"]
    Problem["The Problem<br/>Rideshare platform exploitation<br/>Grid2: pain point cards"]
    Features["Features<br/>Feature cards grid<br/>P2P rides, smart contract escrow"]
    HowItWorks["How It Works<br/>Numbered steps<br/>how-step layout"]
    Comparison["Comparison Table<br/>Ridep2p vs Uber/Lyft<br/>highlight vs dim styling"]
    SmartContracts["Smart Contracts<br/>Contract details<br/>Base L2 deployment info"]
    CTA["CTA Section<br/>Final call to action"]
    Footer["Footer<br/>Domain links + copyright"]

    Nav --> Hero
    Hero --> Problem
    Problem --> Features
    Features --> HowItWorks
    HowItWorks --> Comparison
    Comparison --> SmartContracts
    SmartContracts --> CTA
    CTA --> Footer
```

## Color Accent
- **Primary accent:** `--accent3` (#e8a840 gold)
- **Section label color:** gold
- **Gradient:** gold → pink → purple

## Related Pages
- **Blockchain explorer:** `landing/ridep2p/blockchain/index.html`
- **Portfolio case study:** `portfolio/ridep2p.html`
