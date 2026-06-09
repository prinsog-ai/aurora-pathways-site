# JS Behavior Map (index.html)

All JavaScript is in a single inline `<script>` block (lines 1637–1774 of index.html).

---

## 1. Page Loader

**What:** Removes the full-screen loading overlay once the page finishes loading.

**How:**
- `window.addEventListener('load', ...)` fires.
- Adds `.hidden` class to `.page-loader` (triggers CSS opacity transition).
- Removes `body.loading` class (re-enables scrolling).
- After 500ms, removes the loader element from DOM entirely.

**Dependencies:**
- `.page-loader` element exists in HTML (line 824).
- `body.loading` class set in HTML (line 821).
- CSS: `.page-loader.hidden { opacity: 0; visibility: hidden; }`

**Constraints:** Do NOT remove `body.loading` from the HTML `<body>` tag. The JS removes it.

---

## 2. Cursor Glow

**What:** A 400px radial-gradient circle that smoothly follows the mouse cursor with eased interpolation.

**How:**
- Tracks `mouseX`/`mouseY` from `mousemove` events.
- `requestAnimationFrame` loop applies lerp factor `0.08` to `glowX`/`glowY`.
- Sets `left` and `top` on `#cursorGlow` element.

**Dependencies:**
- Element ID: `#cursorGlow` (line 827). **DO NOT RENAME.**
- CSS: `.cursor-glow { position: fixed; pointer-events: none; z-index: 9999; }`
- Hidden on mobile via `@media (max-width:768px) { .cursor-glow { display: none; } }`

**Constraints:** None beyond the ID.

---

## 3. Aurora Parallax

**What:** Shifts the aurora background layers in response to mouse movement (parallax effect).

**How:**
- Listens for `mousemove` on `document`.
- Calculates offset: `x = (clientX / innerWidth - 0.5) * 20`, same for y.
- Applies CSS `transform: translate(x, y)` on `#auroraBg`.

**Dependencies:**
- Element ID: `#auroraBg` (line 830). **DO NOT RENAME.**
- CSS: `.aurora-bg { transition: transform 0.1s ease-out; }`

**Constraints:** None beyond the ID.

---

## 4. Navbar Scroll Effect

**What:** Shrinks navbar padding and darkens background when user scrolls past 50px.

**How:**
- `window.addEventListener('scroll', ...)` toggles `.scrolled` class on `#navbar` when `scrollY > 50`.

**Dependencies:**
- Element ID: `#navbar` (line 837). **DO NOT RENAME.**
- CSS: `nav.scrolled { padding: 10px 0; background: rgba(10,10,15,0.95); }`

**Constraints:** Threshold is `50` pixels. Adjust in JS if needed.

---

## 5. Scroll Reveal (IntersectionObserver)

**What:** Fades in elements with `.reveal` class when they enter the viewport.

**How:**
- Creates `IntersectionObserver` with `threshold: 0.12`, `rootMargin: '0px 0px -40px 0px'`.
- Selects all `.reveal` elements via `document.querySelectorAll('.reveal')`.
- On intersection, adds `.visible` class and unobserves the element (one-shot animation).

**Dependencies:**
- CSS class `.reveal` on elements. **DO NOT RENAME.**
- CSS class `.visible` added by JS. CSS uses `.reveal.visible` for final state.
- Variants: `.reveal-up`, `.reveal-left`, `.reveal-right`, `.reveal-scale` — all rely on `.visible`.

**Constraints:**
- Observer fires once per element (unobserves after adding `.visible`).
- If new elements are dynamically added, they won't be observed (page is static HTML, so this is fine).
- Threshold `0.12` means 12% of element must be visible. Root margin pulls trigger point 40px above viewport bottom.

---

## 6. Stat Counter Animation

**What:** Animates numbers from 0 to their `data-target` value with ease-out cubic easing over 2 seconds.

**How:**
- Separate `IntersectionObserver` (threshold `0.3`) for `.counter` elements.
- Reads `data-target` attribute for target number.
- Uses `requestAnimationFrame` with cubic ease-out: `1 - Math.pow(1 - progress, 3)`.
- Unobserves after animation completes.

**Dependencies:**
- CSS class `.counter` with `data-target` attribute. **DO NOT RENAME.**
- Currently 4 counters with targets: `174`, `4`, `12`, `2` (lines 931–945).

**Constraints:**
- `data-target` must be an integer.
- Animation duration is `2000` ms (hardcoded).

---

## 7. Live Test Counter Polling

**What:** Polls `/test-count.json` every 30 seconds. If the test count changed, re-animates the first counter.

**How:**
- `setInterval(pollTestCount, 30000)` + immediate call on load.
- Fetches `/test-count.json?t=<timestamp>` (cache-bust).
- Compares `d.tests` with current `data-target` of first `.counter[data-target]` element.
- If different, updates `data-target`, resets text to `'0'`, re-runs animation (1500ms duration).

**Dependencies:**
- File: `/test-count.json` at site root. Must return `{"tests": <number>, ...}`.
- Element: First `.counter[data-target]` in DOM (the "Smart contract tests passing" stat).

**Constraints:**
- Only updates the **first** counter element (the test count one).
- Silently catches errors (endpoint not deployed = no-op).
- 30-second polling interval.

---

## 8. Crypto Price Ticker (CoinGecko API)

**What:** Fetches live crypto prices and updates the scrolling ticker bar.

**How:**
- Calls CoinGecko API: `https://api.coingecko.com/api/v3/simple/price?ids=ethereum,bitcoin,solana,matic-network&vs_currencies=usd&include_24hr_change=true`
- Updates element IDs: `ethPrice`, `ethChange`, `btcPrice`, `btcChange`, `solPrice`, `solChange`, `maticPrice`, `usdcPrice` (hardcoded to `$1.00`).
- Also updates `*2` duplicates for the seamless ticker loop.
- Polls every 60 seconds via `setInterval(fetchPrices, 60000)`.

**Dependencies (DO NOT RENAME THESE IDs):**
- `ethPrice`, `ethPrice2` — ETH price spans
- `ethChange`, `ethChange2` — ETH 24h change spans
- `btcPrice`, `btcPrice2` — BTC price spans
- `btcChange`, `btcChange2` — BTC 24h change spans
- `solPrice`, `solPrice2` — SOL price spans
- `solChange`, `solChange2` — SOL 24h change spans
- `maticPrice`, `maticPrice2` — MATIC price spans
- `usdcPrice`, `usdcPrice2` — USDC price spans (hardcoded to 1.00)

**Constraints:**
- CoinGecko free tier rate limits apply. 60-second interval is safe.
- USDC price is hardcoded to `$1.00`, not fetched.
- Silently catches errors (network failure = no-op, keeps "—" placeholder).
- CSS class `.up` / `.down` on change spans for color styling.

---

## 9. FAQ Toggle (Inline onclick)

**What:** Opens/closes FAQ accordion items on click.

**How:**
- Each `.faq-question` has `onclick="this.parentElement.classList.toggle('open')"`.
- CSS handles the animation via `.faq-item.open .faq-answer { max-height: 300px; }`.

**Dependencies:**
- `.faq-question` elements with inline `onclick` handler.
- `.faq-item` parent with `.open` class toggle.
- `.faq-answer` with CSS `max-height: 0` → `max-height: 300px` transition.

**Constraints:**
- `max-height: 300px` is a fixed value — answers longer than 300px will be clipped.
- This is inline JS, not in the script block. Changing it requires editing the HTML attributes.

---

## External Script Dependencies

| Script | Loaded At | Behavior |
|---|---|---|
| `assets.calendly.com/.../widget.js` | Line 1635, `async` | Renders `.calendly-inline-widget` embed (line 1527). |
| `cloud.umami.is/script.js` | Line 9, `defer` | Analytics tracking. No UI impact. |
