/* Aurora Pathways — Shared dApp UI Enhancement JS
   Provides: skeleton loading, enhanced toasts, accessibility helpers,
   counter animations, transaction progress, wallet prompt. */

const AuroraUI = (() => {

  // ───────────── Skeleton Loading ─────────────

  function showSkeleton(container, count = 3) {
    if (!container) return;
    const html = Array.from({ length: count }, () => `
      <div class="skeleton-card skeleton" aria-hidden="true">
        <div class="skeleton-line short"></div>
        <div class="skeleton-line long"></div>
        <div class="skeleton-line medium"></div>
      </div>
    `).join('');
    container.innerHTML = html;
    container.setAttribute('aria-busy', 'true');
    container.setAttribute('aria-label', 'Loading content...');
  }

  function clearSkeleton(container) {
    if (!container) return;
    container.removeAttribute('aria-busy');
    container.removeAttribute('aria-label');
  }

  // ───────────── Enhanced Toasts ─────────────

  function toast(message, type = 'info', duration = 4000) {
    let container = document.getElementById('toast-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'toast-container';
      container.setAttribute('role', 'status');
      container.setAttribute('aria-live', 'polite');
      container.style.cssText = 'position:fixed;top:20px;right:20px;z-index:10000;display:flex;flex-direction:column;gap:8px;max-width:380px;width:calc(100% - 40px)';
      document.body.appendChild(container);
    }

    const icons = { success: '✓', error: '✕', info: 'ℹ', warning: '⚠' };
    const colors = {
      success: 'rgba(78,201,176,.18)',
      error: 'rgba(255,107,107,.18)',
      info: 'rgba(124,92,252,.18)',
      warning: 'rgba(255,217,61,.18)'
    };

    const el = document.createElement('div');
    el.className = `toast-enhanced`;
    el.style.background = colors[type] || colors.info;
    el.innerHTML = `
      <span style="font-size:15px;flex-shrink:0">${icons[type] || icons.info}</span>
      <span style="flex:1">${message}</span>
      <button onclick="this.parentElement.remove()" aria-label="Dismiss" style="background:none;border:none;color:inherit;cursor:pointer;opacity:.5;font-size:16px;padding:0 2px">✕</button>
    `;

    container.appendChild(el);

    if (duration > 0) {
      setTimeout(() => {
        el.classList.add('hiding');
        setTimeout(() => el.remove(), 300);
      }, duration);
    }

    return el;
  }

  // ───────────── Counter Animation ─────────────

  function animateCounter(el, target, duration = 1000) {
    if (!el || isNaN(target)) return;
    const start = 0;
    const startTime = performance.now();

    function update(currentTime) {
      const elapsed = currentTime - startTime;
      const progress = Math.min(elapsed / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3); // ease-out cubic
      const current = Math.round(start + (target - start) * eased);

      if (target >= 1e6) {
        el.textContent = (current / 1e6).toFixed(1) + 'M';
      } else if (target >= 1e4) {
        el.textContent = (current / 1e3).toFixed(1) + 'K';
      } else {
        el.textContent = current.toLocaleString();
      }

      if (progress < 1) {
        requestAnimationFrame(update);
      }
    }

    requestAnimationFrame(update);
  }

  // ───────────── Transaction Progress ─────────────

  function txProgress(steps) {
    // steps: [{ label, status: 'pending'|'active'|'done'|'error' }]
    const html = `<div class="milestone-tracker" role="progressbar" aria-label="Transaction progress">
      ${steps.map((s, i) => {
        let cls = s.status || 'pending';
        let icon = cls === 'done' ? '✓' : cls === 'error' ? '✕' : cls === 'active' ? '●' : (i + 1);
        let dot = `<div class="milestone-dot">${icon}</div>`;
        let label = `<div class="milestone-label">${s.label}</div>`;
        let line = i < steps.length - 1 ? `<div class="milestone-line ${cls === 'done' ? 'done' : ''}"></div>` : '';
        return `<div class="milestone-step ${cls}">${dot}${label}</div>${line}`;
      }).join('')}
    </div>`;
    return html;
  }

  // ───────────── Empty State ─────────────

  function emptyState(icon, title, desc, actionHtml = '') {
    return `
      <div class="empty-state" role="status">
        <div class="empty-state-icon" aria-hidden="true">${icon}</div>
        <div class="empty-state-title">${title}</div>
        <div class="empty-state-desc">${desc}</div>
        ${actionHtml ? `<div class="empty-state-action">${actionHtml}</div>` : ''}
      </div>
    `;
  }

  // ───────────── Wallet Prompt ─────────────

  function walletPrompt(onConnect) {
    return `
      <div class="wallet-prompt" role="dialog" aria-label="Connect wallet">
        <div class="wallet-prompt-icon" aria-hidden="true">🔗</div>
        <div class="wallet-prompt-title">Connect Your Wallet</div>
        <div class="wallet-prompt-desc">
          Connect your wallet to start using the dApp. You'll need a Polygon-compatible wallet like MetaMask or Coinbase Wallet.
        </div>
        <button class="btn btn-primary btn-micro ripple" onclick="(${onConnect.toString()})()" aria-label="Connect wallet">
          Connect Wallet
        </button>
      </div>
    `;
  }

  // ───────────── Stat Cards ─────────────

  function statCard(value, label, change = null) {
    let changeHtml = '';
    if (change !== null) {
      const cls = change >= 0 ? 'up' : 'down';
      const arrow = change >= 0 ? '↑' : '↓';
      changeHtml = `<div class="stat-change ${cls}">${arrow} ${Math.abs(change)}%</div>`;
    }
    return `
      <div class="stat-card-enhanced card-hover">
        <div class="stat-value" data-counter="${value}">${value}</div>
        <div class="stat-label">${label}</div>
        ${changeHtml}
      </div>
    `;
  }

  // ───────────── Status Badge ─────────────

  function statusBadge(status) {
    const map = {
      'Open': 'status-open',
      'InProgress': 'status-progress',
      'In Progress': 'status-progress',
      'Completed': 'status-completed',
      'Cancelled': 'status-cancelled',
      'Disputed': 'status-disputed',
      'Pending': 'status-pending',
      'Released': 'status-completed',
      'Refunded': 'status-cancelled',
    };
    const cls = map[status] || 'status-pending';
    return `<span class="status-badge ${cls}" role="status">${status}</span>`;
  }

  // ───────────── Accessibility: ARIA Helpers ─────────────

  function makeAccessible(el, label, role) {
    if (!el) return;
    if (label) el.setAttribute('aria-label', label);
    if (role) el.setAttribute('role', role);
  }

  function announceToScreenReader(message) {
    const el = document.createElement('div');
    el.setAttribute('role', 'status');
    el.setAttribute('aria-live', 'assertive');
    el.className = 'sr-only';
    el.textContent = message;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 3000);
  }

  // ───────────── Public API ─────────────

  return {
    showSkeleton,
    clearSkeleton,
    toast,
    animateCounter,
    txProgress,
    emptyState,
    walletPrompt,
    statCard,
    statusBadge,
    makeAccessible,
    announceToScreenReader,
  };
})();
