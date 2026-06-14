# Aurora Pathways — Portfolio Map

**Last updated: June 14, 2026**

## Industry Demos (13 total)
| Industry | File | URL |
|---|---|---|
| Real Estate | demos/buildium/ | https://buildium-two.vercel.app |
| Healthcare | demos/carecloud/ | https://carecloud-lac.vercel.app |
| Finance | demos/lendingclub/ | https://lendingclub-eta.vercel.app |
| Supply Chain | demos/buildium/ | https://buildium-two.vercel.app |
| Art & Entertainment | demos/distrokid/ | https://distrokid.vercel.app |
| Gaming & Esports | demos/100thieves/ | https://100thieves.vercel.app |
| Education | demos/credly/ | https://credly-lake.vercel.app |
| Government | demos/granicus/ | https://granicus.vercel.app |
| DAO & Governance | demos/snapshot/ | https://snapshot-flax.vercel.app |
| Retail & Ecommerce | demos/yotpo/ | https://yotpo-flax.vercel.app |
| Legal | demos/ironclad/ | https://ironclad-lyart.vercel.app |
| Energy | portfolio/energy-carbon.html | https://aurorapathways.xyz/portfolio/energy-carbon.html |
| RWA Tokenization | demos/centrifuge/ | https://centrifuge-plum.vercel.app |

## Client Demos (4 total)
| Client | URL |
|---|---|
| Valence | https://valence-demo-theta.vercel.app |
| WES | https://wes-demo-ten.vercel.app |
| Acme | https://acme-demo-two.vercel.app |
| Noble | https://noble-demo-dusky.vercel.app |

## Client Production Platforms (4 total)
| Client | URL |
|---|---|
| Valence | https://valence-platform.vercel.app |
| WES | https://wes-platform-henna.vercel.app |
| Acme | https://acme-platform.vercel.app |
| Noble | https://noble-platform-omega.vercel.app |

## ERES (Client Prospect — NOT an industry demo)
| Demo | URL |
|---|---|
| ERES Companies | https://eres-woad.vercel.app |

## DAO dApps (4 total)
| Protocol | dApp URL | Landing URL | Custom Domain |
|---|---|---|---|
| Tasklync | https://dapp-zeta-pink.vercel.app | /landing/tasklync/ | tasklync.xyz |
| Pledgly | https://pledgly.vercel.app | /landing/pledgly/ | pledgly.xyz |
| Forekast | https://forekast-teal.vercel.app | /landing/forekast/ | forekastdao.xyz |
| RideP2P | https://ridep2p.vercel.app | /landing/ridep2p/ | ridep2p.xyz |

## Main Site
| Page | URL |
|---|---|
| Main site | https://aurorapathways.xyz |
| Dashboard | https://dashboard-ashen-phi-69.vercel.app |
| Logo concepts | https://logo-concepts-ruby.vercel.app |

## Custom Domains
| Domain | Target |
|---|---|
| aurorapathways.xyz | Main site (Vercel) |
| tasklync.xyz | Tasklync landing page |
| pledgly.xyz | Pledgly landing page |
| forekastdao.xyz | Forekast landing page |
| ridep2p.xyz | RideP2P landing page |

## Link Flow (CRITICAL — do not break)
- Main site "Launch dApp" → goes to LANDING PAGE (not directly to dApp)
- Landing page "Launch App" → goes to dApp
- Main site "View demo" → goes to industry demo
- Energy demo lives at /portfolio/energy-carbon.html on main site (NOT on Vercel)

## What NOT to do
- Do NOT point industry demos to client pitches (ERES ≠ energy demo)
- Do NOT point "Launch dApp" directly to dApp — must go through landing page first
- Do NOT deploy landing pages to dApp Vercel projects
- Do NOT add fake testimonials
- Do NOT change links without verifying the target exists and works
