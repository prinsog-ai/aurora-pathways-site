# Forekast Landing Page Map

**File:** `landing/forekast/index.html`
**URL:** `/landing/forekast/`
**Title:** Forekast — Decentralized Prediction Markets

## Section Flow

```mermaid
flowchart TD
    Nav["Nav Bar<br/>Logo + Get in Touch CTA"]
    Hero["Hero Section<br/>Badge: Built by Aurora Pathways<br/>Title + Description<br/>Stats: prediction market metrics<br/>CTA buttons"]
    Problem["The Problem<br/>Centralized prediction market issues<br/>Grid2: pain point cards"]
    Features["Features<br/>Feature cards grid<br/>Multi-oracle resolution, YES/NO tokens"]
    HowItWorks["How It Works<br/>Numbered steps<br/>how-step layout"]
    Comparison["Comparison Table<br/>Forekast vs Polymarket/Kalshi<br/>highlight vs dim styling"]
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
- **Primary accent:** `--accent2` (#4ec9b0 teal)
- **Section label color:** teal
- **Gradient:** reversed (teal → blue → purple)

## Related Pages
- **Blockchain explorer:** `landing/forekast/blockchain/index.html`
- **Portfolio case study:** `portfolio/forekast.html`
