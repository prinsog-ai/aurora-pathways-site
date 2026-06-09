# Tasklync Landing Page Map

**File:** `landing/tasklync/index.html`
**URL:** `/landing/tasklync/`
**Title:** Tasklync — Permissionless Freelance Marketplace

## Section Flow

```mermaid
flowchart TD
    Nav["Nav Bar<br/>Logo + Get in Touch CTA"]
    Hero["Hero Section<br/>Badge: Built by Aurora Pathways<br/>Title + Description<br/>Stats: 3% fee, Instant USDC, $0.01 gas<br/>CTA: View Full Demo / Book a Call"]
    Problem["The Problem<br/>Freelancers gutted by fees<br/>Grid2: pain point cards"]
    Features["Features<br/>Feature cards grid<br/>Key platform capabilities"]
    HowItWorks["How It Works<br/>Numbered steps<br/>how-step layout"]
    Comparison["Comparison Table<br/>Tasklync vs Upwork/Fiverr<br/>highlight vs dim styling"]
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
- **Primary accent:** `--accent` (#7c5cfc purple)
- **Section label color:** purple
- **Stat values:** `--accent2` (#4ec9b0 teal)

## Related Pages
- **Blockchain explorer:** `landing/tasklync/blockchain/index.html`
- **dApp:** `landing/tasklync/dapp/index.html`
- **Portfolio case study:** `portfolio/tasklync.html`
