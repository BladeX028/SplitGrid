/* ================================================================
   SplitGrid · Shared Data & Utilities
   Colombia · Brasil · Francia · Italia · Rusia
   ================================================================ */

// ── SUPPORTED COUNTRIES (solo los 5 del proyecto + fallback) ──
const COUNTRIES = {
  CO:{name:'Colombia',    flag:'🇨🇴',currency:'COP',sym:'$',    tax:19, tip:10, locale:'es-CO',
      methods:[
        {icon:'💙',name:'Nequi',      sub:'Pago instantáneo',     bg:'linear-gradient(135deg,rgba(59,110,250,.25),rgba(6,182,212,.2))'},
        {icon:'💚',name:'Daviplata',  sub:'Pago móvil',           bg:'linear-gradient(135deg,rgba(34,197,94,.2),rgba(5,150,105,.15))'},
        {icon:'🏦',name:'PSE',        sub:'Débito bancario',      bg:'linear-gradient(135deg,rgba(245,158,11,.2),rgba(217,119,6,.15))'},
        {icon:'💳',name:'Tarjeta',    sub:'Visa, Mastercard',     bg:'var(--bg4)'},
        {icon:'💵',name:'Efectivo',     sub:'Punto físico',         bg:'var(--bg4)'},
      ]},
  BR:{name:'Brasil',      flag:'🇧🇷',currency:'BRL',sym:'R$',   tax:0,  tip:10, locale:'pt-BR',
      methods:[
        {icon:'🟩',name:'PIX',        sub:'Pagamento instantâneo',bg:'linear-gradient(135deg,rgba(34,197,94,.2),rgba(5,150,105,.15))'},
        {icon:'📄',name:'Boleto',     sub:'Boleto bancário',      bg:'var(--bg4)'},
        {icon:'💳',name:'Cartão',     sub:'Crédito / débito',     bg:'var(--bg4)'},
      ]},
  FR:{name:'France',      flag:'🇫🇷',currency:'EUR',sym:'€',    tax:20, tip:0,  locale:'fr-FR',
      methods:[
        {icon:'💳',name:'Carte Bleue',sub:'Paiement sécurisé',   bg:'var(--bg4)'},
        {icon:'🍎',name:'Apple Pay',  sub:'Paiement mobile',      bg:'var(--bg4)'},
        {icon:'🔵',name:'Google Pay', sub:'Paiement mobile',      bg:'var(--bg4)'},
        {icon:'🏦',name:'Virement',   sub:'Virement bancaire',    bg:'var(--bg4)'},
      ]},
  IT:{name:'Italia',      flag:'🇮🇹',currency:'EUR',sym:'€',    tax:22, tip:0,  locale:'it-IT',
      methods:[
        {icon:'💳',name:'Carta',      sub:'Credito / debito',     bg:'var(--bg4)'},
        {icon:'🏦',name:'Bonifico',   sub:'Bonifico bancario',    bg:'var(--bg4)'},
        {icon:'🍎',name:'Apple Pay',  sub:'Pagamento mobile',     bg:'var(--bg4)'},
        {icon:'🔵',name:'Satispay',   sub:'App di pagamento',     bg:'linear-gradient(135deg,rgba(239,68,68,.2),rgba(185,28,28,.15))'},
      ]},
  RU:{name:'Россия',      flag:'🇷🇺',currency:'RUB',sym:'₽',    tax:20, tip:0,  locale:'ru-RU',
      methods:[
        {icon:'⚡',name:'СБП',        sub:'Система быстрых платежей',bg:'linear-gradient(135deg,rgba(59,110,250,.2),rgba(6,182,212,.15))'},
        {icon:'💳',name:'Мир',        sub:'Национальная карта',   bg:'linear-gradient(135deg,rgba(34,197,94,.15),rgba(5,150,105,.1))'},
        {icon:'💳',name:'YooMoney',   sub:'Электронный кошелёк',  bg:'var(--bg4)'},
      ]},
};

// Geo-IP mapping by timezone offset / language (best-effort without server)
const TIMEZONE_COUNTRY_MAP = {
  'America/Bogota':'CO','America/Bogotá':'CO',
  'America/Sao_Paulo':'BR','America/Manaus':'BR','America/Belem':'BR',
  'America/Fortaleza':'BR','America/Recife':'BR','America/Bahia':'BR',
  'Europe/Paris':'FR',
  'Europe/Rome':'IT',
  'Europe/Moscow':'RU','Europe/Samara':'RU','Europe/Kaliningrad':'RU',
  'Asia/Yekaterinburg':'RU','Asia/Omsk':'RU','Asia/Novosibirsk':'RU',
  'Asia/Irkutsk':'RU','Asia/Yakutsk':'RU','Asia/Vladivostok':'RU',
};

const SUPPORTED_LANGS = {
  'es':'CO','es-CO':'CO','es-419':'CO',
  'pt':'BR','pt-BR':'BR',
  'fr':'FR','fr-FR':'FR','fr-BE':'FR',
  'it':'IT','it-IT':'IT',
  'ru':'RU','ru-RU':'RU',
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

// ── GEO DETECTION ──
function detectCountry() {
  // 1. Try timezone
  try {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (TIMEZONE_COUNTRY_MAP[tz]) return TIMEZONE_COUNTRY_MAP[tz];
  } catch(e){}

  // 2. Try browser language
  const langs = navigator.languages || [navigator.language];
  for (const lang of langs) {
    if (SUPPORTED_LANGS[lang]) return SUPPORTED_LANGS[lang];
    const base = lang.split('-')[0];
    if (SUPPORTED_LANGS[base]) return SUPPORTED_LANGS[base];
  }

  // 3. Default to Colombia
  return 'CO';
}

// ── FORMATTING ──
function fmt(n, countryCode) {
  const c = COUNTRIES[countryCode] || COUNTRIES.CO;
  return c.sym + ' ' + Math.round(n).toLocaleString(c.locale);
}

function initials(name) {
  if (!name) return '?';
  return name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase();
}

function genCode() {
  const ch = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return Array.from({length: 6}, () => ch[Math.floor(Math.random() * ch.length)]).join('');
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
    user: null, country: detectCountry(), session: null, payments: [], menu: []
  };
}
function saveClientState(st) {
  localStorage.setItem('splitgrid_client', JSON.stringify(st));
}

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

// ── SESSION MATH ──
function sessionSubtotal(s, menu) {
  return (s.orders || []).reduce((t, o) => {
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
  (s.orders || []).forEach(o => {
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
