/* ================================================================
   SplitGrid · Shared Data & Utilities
   Colombia
   ================================================================ */

// ── COLOMBIA ──
const COUNTRIES = {
  CO:{name:'Colombia', flag:'🇨🇴', currency:'COP', sym:'$', tax:19, tip:10, locale:'es-CO',
      methods:[
        {icon:'💙',name:'Nequi',             sub:'Código QR / número',    bg:'linear-gradient(135deg,rgba(59,110,250,.25),rgba(6,182,212,.2))'},
        {icon:'💚',name:'Daviplata',         sub:'Pago móvil',             bg:'linear-gradient(135deg,rgba(34,197,94,.2),rgba(5,150,105,.15))'},
        {icon:'🔐',name:'Llave Bancolombia', sub:'App Bancolombia',        bg:'linear-gradient(135deg,rgba(245,158,11,.2),rgba(217,119,6,.15))'},
        {icon:'🏦',name:'PSE',               sub:'Débito bancario',        bg:'linear-gradient(135deg,rgba(100,116,139,.2),rgba(71,85,105,.15))'},
        {icon:'💳',name:'Tarjeta',           sub:'Débito / Crédito',       bg:'var(--bg4)'},
        {icon:'💵',name:'Efectivo',          sub:'Pago en caja',           bg:'var(--bg4)'},
      ]},
};

const AV_COLORS = [
  'linear-gradient(135deg,#3B6EFA,#7B2FBE)',
  'linear-gradient(135deg,#22C55E,#16A34A)',
  'linear-gradient(135deg,#F59E0B,#D97706)',
  'linear-gradient(135deg,#EF4444,#B91C1C)',
  'linear-gradient(135deg,#A855F7,#7C3AED)',
  'linear-gradient(135deg,#06B6D4,#0284C7)',
  'linear-gradient(135deg,#F97316,#C2410C)',
  'linear-gradient(135deg,#10B981,#059669)',
];

// ── FORMATTING ──
function fmt(n) {
  return '$ ' + Math.round(n).toLocaleString('es-CO');
}

function initials(name) {
  if (!name) return '?';
  return name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase();
}

function genCode() {
  const ch = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return Array.from({length: 6}, () => ch[Math.floor(Math.random() * ch.length)]).join('');
}

// ID de sesión único entre restaurantes (antes era 1, 2, 3… por restaurante y chocaba en Supabase).
// Numérico (< Number.MAX_SAFE_INTEGER) para seguir funcionando donde el código espera un número.
let _sidLast = 0, _sidSeq = Math.floor(Math.random() * 1000);
function genSessionId() {
  // milisegundos × 1000 + secuencia (arranca aleatoria): nunca se repite en este navegador
  // y es muy improbable que coincida con otro restaurante; sbSyncDB además evita pisar sesiones ajenas.
  let id = Date.now() * 1000 + (_sidSeq++ % 1000);
  if (id <= _sidLast) id = _sidLast + 1;
  _sidLast = id;
  return id;
}

function elapsedMin(ts) {
  return Math.floor((Date.now() - new Date(ts).getTime()) / 60000);
}

// ── SHARED STATE (localStorage) ──
function loadRestDB() {
  return JSON.parse(localStorage.getItem('splitgrid_restaurant') || 'null');
}
function saveRestDB(db, _skipSupabase) {
  localStorage.setItem('splitgrid_restaurant', JSON.stringify(db));
  if (!_skipSupabase && typeof sbSyncDB === 'function') sbSyncDB(db).catch(() => {});
}
function loadClientState() {
  return JSON.parse(localStorage.getItem('splitgrid_client') || 'null') || {
    user: null, country: 'CO', session: null, payments: [], menu: []
  };
}
function saveClientState(st) {
  localStorage.setItem('splitgrid_client', JSON.stringify(st));
}

// ── CELULAR: la página nunca debe quedar desplazada ──
// La app se desplaza dentro de .content; si el navegador mueve la página completa
// (teclado, focus() de un input), la barra superior queda fuera de pantalla y no se puede volver.
(function keepAppPinnedTop() {
  if (typeof window === 'undefined' || typeof document === 'undefined') return;
  const typing = () => {
    const a = document.activeElement;
    return !!a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.tagName === 'SELECT' || a.isContentEditable);
  };
  const reset = () => {
    if (!document.getElementById('app')) return; // solo en las vistas de la app (no en la landing)
    if (typing()) return;                         // con el teclado abierto, dejar que el navegador muestre el campo
    const se = document.scrollingElement || document.documentElement;
    if (se && (se.scrollTop || se.scrollLeft)) { se.scrollTop = 0; se.scrollLeft = 0; }
    if (document.body && (document.body.scrollTop || document.body.scrollLeft)) { document.body.scrollTop = 0; document.body.scrollLeft = 0; }
  };
  window.addEventListener('scroll', reset, { passive: true });
  document.addEventListener('focusout', () => setTimeout(reset, 50));
  if (window.visualViewport) window.visualViewport.addEventListener('resize', () => setTimeout(reset, 50));
  window.addEventListener('orientationchange', () => setTimeout(reset, 300));
})();

// ── TOAST ──
function toast(msg, dur = 2800) {
  const el = document.getElementById('toast');
  if (!el) return;
  document.getElementById('toast-msg').textContent = msg;
  el.classList.add('show');
  clearTimeout(el._t);
  el._t = setTimeout(() => el.classList.remove('show'), dur);
}

// ── MODAL ──
function openModal(id) { document.getElementById(id)?.classList.add('open'); }
function closeModal(id) { document.getElementById(id)?.classList.remove('open'); }

// ── ESTADOS DE PEDIDO ──
// review    → En revisión: lo registró el cliente, el restaurante debe confirmarlo o cancelarlo.
//             Aparta unidades del inventario pero aún NO se cobra.
// preparing → En preparación: confirmado; aquí se descuenta del inventario.
// delivered → Entregado.
// Cancelar = el pedido se elimina de la cuenta y, si ya se había descontado, vuelve al inventario.
const ORDER_STATUS = {
  review:    { label: 'En revisión',    badge: 'badge-amber', icon: '⏳' },
  preparing: { label: 'En preparación', badge: 'badge-blue',  icon: '👨‍🍳' },
  delivered: { label: 'Entregado',      badge: 'badge-green', icon: '✅' },
};
function orderStatus(o) { return (o && ORDER_STATUS[o.status]) ? o.status : 'preparing'; }
function isBillable(o) { return orderStatus(o) !== 'review'; }
function orderStatusBadge(o, style = '') {
  const st = ORDER_STATUS[orderStatus(o)];
  let html = `<span class="badge ${st.badge}" style="${style}">${st.icon} ${st.label}</span>`;
  if (o.cancelRequested) html += `<span class="badge badge-red" style="${style}">✋ Cancelación solicitada</span>`;
  return html;
}

// ── INVENTARIO ──
// m.stock = unidades en inventario que el restaurante define (null/undefined = sin límite).
// Al pasar un pedido a "En preparación" se descuenta de m.stock (o.stockApplied = true).
// Los pedidos que aún no se descuentan (En revisión) apartan unidades: disponible = stock - apartado.
const MAX_QTY_PER_ORDER = 20; // tope de seguridad por pedido desde la app del cliente

function hasStock(m) {
  return !!m && m.stock !== null && m.stock !== undefined && m.stock !== '' && !isNaN(m.stock);
}
function _openSessions(sessions) {
  return (sessions || []).filter(s => s && (s.status === 'occupied' || s.status === 'paying'));
}
// Unidades apartadas por pedidos que todavía no se descuentan del inventario
function reservedQty(sessions, menuItemId) {
  return _openSessions(sessions).reduce((t, s) => t + (s.orders || [])
    .filter(o => o.menuItemId === menuItemId && !o.stockApplied)
    .reduce((a, o) => a + (Number(o.qty) || 0), 0), 0);
}
// Unidades disponibles para pedir ahora (Infinity si el plato no maneja inventario)
function availableQty(m, sessions) {
  if (!hasStock(m)) return Infinity;
  return Math.max(0, Number(m.stock) - reservedQty(sessions, m.id));
}
// Descuenta del inventario un pedido (al pasar a "En preparación"). Idempotente.
function applyOrderStock(menu, o) {
  if (o.stockApplied) return;
  const mi = (menu || []).find(m => m.id === o.menuItemId);
  const n = hasStock(mi) ? (Number(o.qty) || 0) : 0;
  if (n) mi.stock = Math.max(0, Number(mi.stock) - n);
  o.stockApplied = true;
  o.stockQty = n; // lo que realmente se descontó (para devolverlo si se cancela)
}
// Devuelve al inventario lo que un pedido había descontado (al cancelarlo)
function restoreOrderStock(menu, o) {
  if (!o.stockApplied || !o.stockQty) return;
  const mi = (menu || []).find(m => m.id === o.menuItemId);
  if (hasStock(mi)) mi.stock = Number(mi.stock) + Number(o.stockQty);
}
// Al cerrar una mesa: descuenta pedidos antiguos que nunca pasaron por el flujo de estados
function consumeStock(menu, session) {
  (session.orders || []).forEach(o => applyOrderStock(menu, o));
}
function parseStockInput(val) {
  const v = String(val ?? '').trim();
  if (v === '') return null;
  const n = parseInt(v, 10);
  return isNaN(n) || n < 0 ? NaN : n;
}

// ── SESSION MATH ──
function sessionSubtotal(s, menu) {
  return (s.orders || []).filter(isBillable).reduce((t, o) => {
    const mi = menu.find(m => m.id === o.menuItemId);
    return t + (mi ? mi.price * o.qty : 0);
  }, 0);
}
// IVA included in prices — returns subtotal only (tip is optional and separate)
function sessionTotal(s, menu) {
  return sessionSubtotal(s, menu);
}
function calcPersonTotal(s, personId, menu) {
  let sub = 0;
  (s.orders || []).filter(isBillable).forEach(o => {
    const mi = menu.find(m => m.id === o.menuItemId);
    if (!mi) return;
    if (o.type === 'individual' && o.personId === personId) sub += mi.price * o.qty;
    if (o.type === 'shared') {
      const divisor = o.sharedWith && Array.isArray(o.sharedWith)
        ? o.sharedWith.length
        : (typeof o.sharedWith === 'number' ? o.sharedWith : (s.participants?.length || 1));
      const inList = !Array.isArray(o.sharedWith)
        || o.sharedWith.includes(personId)
        || o.sharedWith.includes('ALL');
      if (inList) sub += mi.price * o.qty / divisor;
    }
  });
  // IVA included in price — no separate tax
  const tipRate = (s.tip || 0) / 100;
  const tip = sub * tipRate;
  // Add any debt transferred to this person when another participant was removed
  const transferred = (s.transferredDebts || [])
    .filter(td => td.toPersonId === personId)
    .reduce((t, td) => t + td.amount, 0);
  // total does NOT include tip — tip is optional and tracked separately
  return { sub, tax: 0, tip, total: sub + transferred };
}
