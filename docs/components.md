# Component & Section Inventory

## Reusable CSS Components (index.html)

### `.page-loader`
- **What:** Full-screen loading overlay with animated gradient bar.
- **Where:** index.html only.
- **Key classes:** `.page-loader`, `.hidden`, `.loader-bar`
- **Safe changes:** Bar color, animation speed, opacity transition timing.
- **Must NOT change:** `body.loading` class toggle logic (JS removes it on `window.load`).

### `.cursor-glow`
- **What:** 400px radial-gradient circle that follows mouse cursor.
- **Where:** index.html only.
- **Key classes:** `.cursor-glow`, ID `#cursorGlow`
- **Safe changes:** Glow size, color, opacity, blur radius.
- **Must NOT change:** ID `cursorGlow` (used by JS). Hidden on mobile via `@media (max-width:768px)`.

### `.aurora-bg`
- **What:** Fixed parallax background with 3 blurred color layers.
- **Where:** index.html (div with JS parallax). Landing/blog pages use CSS-only `radial-gradient` background.
- **Key classes:** `.aurora-bg`, `.aurora-layer`, `.aurora-layer-1/2/3`, ID `#auroraBg`
- **Safe changes:** Layer colors, positions, blur amounts.
- **Must NOT change:** ID `auroraBg` (used by JS mousemove parallax).

### `nav` / `#navbar`
- **What:** Fixed top navigation bar with glass-morphism backdrop blur.
- **Where:** index.html. Landing pages have their own simpler navs.
- **Key classes:** `nav`, `.scrolled`, `.logo`, `.nav-links`, `.nav-cta`, ID `#navbar`
- **Safe changes:** Link labels, href targets, padding, blur amount.
- **Must NOT change:** ID `navbar` (used by JS scroll handler). `nav .scrolled` class toggled by JS at scrollY > 50.

### `.hero`
- **What:** Full-viewport hero section with badge, h1, description, CTA buttons.
- **Where:** index.html, landing pages (variations).
- **Key classes:** `.hero`, `.hero-content`, `.hero-badge`, `.hero-desc`, `.hero-buttons`
- **Safe changes:** Text content, button labels/links, badge text, padding.
- **Must NOT change:** `.hero` min-height or flex alignment (breaks layout).

### `.btn-primary` / `.btn-secondary` / `.btn-demo`
- **What:** Three button variants. Primary = gradient fill. Secondary = glass border. Demo = accent2 outline.
- **Where:** index.html, portfolio pages (`.btn-primary`, `.btn-outline`), landing pages.
- **Safe changes:** Padding, font-size, border-radius, colors.
- **Must NOT change:** Class names (referenced in HTML throughout).

### `.section-label` / `.section-divider` / `.section-desc`
- **What:** Standard section header pattern: uppercase pill label → divider line → h2 → description paragraph.
- **Where:** Every section in index.html.
- **Safe changes:** Text content, colors, spacing.
- **Must NOT change:** Class names or structure (CSS grid/layout depends on it).

### `.reveal` / `.reveal-up` / `.reveal-left` / `.reveal-scale`
- **What:** Scroll-triggered entrance animations via IntersectionObserver.
- **Where:** index.html, landing pages.
- **Key classes:** `.reveal`, `.visible` (added by JS), `.reveal-up`, `.reveal-left`, `.reveal-right`, `.reveal-scale`
- **Safe changes:** Animation duration, easing, transform distances, delay.
- **Must NOT change:** Class `.reveal` (selected by JS observer). Class `.visible` (toggled by JS). Do NOT rename.

### `.services-grid` / `.service-card`
- **What:** Auto-fit CSS grid of cards. Used for services, portfolio, blog previews.
- **Where:** index.html (#services, #portfolio, #blog sections).
- **Key classes:** `.services-grid`, `.service-card`, `.service-icon`, `.tech-tags`, `.tech-tag`
- **Safe changes:** Grid minmax size, gap, card padding, icon size.
- **Must NOT change:** `.service-card` structure (icon → h3 → p → tags).

### `.pricing-grid` / `.pricing-card`
- **What:** 3-column pricing card grid. Featured card has gradient border.
- **Where:** index.html (#pricing, #why-web3, #crypto-payments, #capabilities).
- **Key classes:** `.pricing-grid`, `.pricing-card`, `.featured`, `.pricing-badge`, `.price-tag`, `.pricing-features`
- **Safe changes:** Prices, feature lists, grid gap, card padding.
- **Must NOT change:** `.featured` class (controls gradient border mask technique).

### `.timeline` / `.timeline-phase`
- **What:** Vertical timeline with dot markers and left-border line.
- **Where:** index.html (#timeline section only).
- **Key classes:** `.timeline`, `.timeline-phase`
- **Safe changes:** Step content, colors, spacing, dot size.
- **Must NOT change:** `.timeline` padding-left (aligns with pseudo-element line).

### `.stats-row` / `.stat-item` / `.stat-value` / `.stat-label`
- **What:** Horizontal row of stat counters with gradient text.
- **Where:** index.html (stats section, trust-bar).
- **Key classes:** `.stats-row`, `.stat-item`, `.stat-value`, `.stat-label`, `.counter[data-target]`
- **Safe changes:** Layout, spacing, font sizes.
- **Must NOT change:** `.counter` class and `data-target` attribute (JS reads these for animation).

### `.ticker-bar` / `.ticker-track` / `.ticker-item`
- **What:** Horizontally scrolling crypto price ticker bar.
- **Where:** index.html (after hero). `.ticker-bar` class reused for stats section.
- **Key classes:** `.ticker-bar`, `.ticker-track`, `.ticker-item`, `.price`, `.change`, `.up`, `.down`
- **Safe changes:** Animation speed, item gap, font sizes.
- **Must NOT change:** Element IDs for price spans (see js-behavior.md). Ticker uses CSS `translateX(-50%)` — content must be duplicated for seamless loop.

### `.faq-item` / `.faq-question` / `.faq-answer`
- **What:** Accordion FAQ with toggle-on-click.
- **Where:** index.html (#faq section).
- **Key classes:** `.faq-item`, `.open`, `.faq-question`, `.faq-answer`
- **Safe changes:** Content, spacing, animation timing, icon style.
- **Must NOT change:** `onclick="this.parentElement.classList.toggle('open')"` on `.faq-question` (inline handler). `.open` class drives CSS max-height transition.

### `.trust-bar`
- **What:** Bottom stats bar showing deployment metrics.
- **Where:** index.html (before blog section).
- **Key classes:** `.trust-bar`, `.trust-logos`
- **Safe changes:** Metrics values, layout, spacing.
- **Must NOT change:** None critical. Static HTML, no JS dependency.

### `.glass-card`
- **What:** Generic glass-morphism card with blur backdrop.
- **Where:** index.html CSS (defined but primarily used via inline styles in sections).
- **Safe changes:** Any visual properties.
- **Must NOT change:** None critical.

## Portfolio Pages (portfolio/*.html)

### `.back`
- **What:** "← Back to Portfolio" link.
- **Where:** All 18 portfolio pages + ipfs-deploy.html.
- **Key classes:** `.back`
- **Safe changes:** Color, font-size.
- **Must NOT change:** `href="../index.html#portfolio"` — ensures return navigation works.

### `.card` / `.grid` / `.grid-3`
- **What:** Content cards and grid layouts for case study details.
- **Where:** portfolio/tasklync.html and similar protocol case studies.
- **Safe changes:** Any visual properties.
- **Must NOT change:** None critical.

## Landing Pages (landing/*/index.html)

### Scroll-reveal (landing pages)
- **What:** Simpler `.reveal` implementation. Same class names as index.html.
- **Where:** All landing page index files.
- **Must NOT change:** `.reveal` / `.visible` class names.

### Wallet Connect (`#connectBtn`)
- **What:** MetaMask wallet connection button.
- **Where:** `landing/tasklync/blockchain/index.html` and other blockchain subpages.
- **Key classes:** `#connectBtn`, `.connected`, `#walletAddr`
- **Must NOT change:** Button ID `connectBtn` (used by ethers.js wallet connect script).
