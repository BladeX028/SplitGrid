/* ================================================================
   SplitGrid · Capa de integración con Supabase
   Depende de: @supabase/supabase-js cargado desde CDN
   ================================================================ */

const _SB_URL  = 'https://jqwgmxavuvaklbszmfkp.supabase.co';
const _SB_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impxd2dteGF2dXZha2xic3ptZmtwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk0NTU5MDYsImV4cCI6MjA5NTAzMTkwNn0.sS8UhdPm-2VzD4e8T6k2O4S6xo6FMb5D_GpSFaVJKM0';

const _sb = supabase.createClient(_SB_URL, _SB_ANON);

// ── HELPERS ────────────────────────────────────────────────────

function _j(val) {
  if (Array.isArray(val) || (val && typeof val === 'object')) return val;
  if (typeof val === 'string') { try { return JSON.parse(val); } catch { return []; } }
  return [];
}

function _rowToSession(row) {
  return {
    id:               isNaN(row.id) ? row.id : Number(row.id),
    restaurantId:     row.restaurant_id,
    tableNumber:      row.table_number,
    tableId:          isNaN(row.table_id) ? row.table_id : Number(row.table_id),
    joinCode:         row.join_code,
    status:           row.status,
    splitMode:        row.split_mode || 'by_item',
    tax:              Number(row.tax),
    tip:              Number(row.tip),
    participants:     _j(row.participants),
    orders:           _j(row.orders),
    payments:         _j(row.payments),
    transferredDebts: _j(row.transferred_debts),
    openedAt:         row.opened_at,
    closedAt:         row.closed_at || null,
  };
}

// ── RESTAURANTE ────────────────────────────────────────────────

async function sbSaveRestaurant(db) {
  if (!db?._loginEmail) return;
  const { error } = await _sb.from('sg_restaurants').upsert({
    id:               db._loginEmail,
    name:             db.restaurant.name,
    country:          db.restaurant.country,
    tax:              db.restaurant.tax,
    tip:              db.restaurant.tip,
    num_tables:       db.restaurant.numTables,
    address:          db.restaurant.address || '',
    menu:             db.menu,
    tables_data:      db.tables,
    next_menu_id:     db.nextMenuId,
    next_session_id:  db.nextSessionId,
    payment_accounts: db.restaurant.paymentAccounts || {},
    dlocal_url:       db.restaurant.dlocalUrl || '',
    updated_at:       new Date().toISOString(),
  }, { onConflict: 'id' });
  if (error) console.warn('sbSaveRestaurant:', error.message);
}

async function sbLoadRestaurant(email) {
  const { data, error } = await _sb
    .from('sg_restaurants').select('*').eq('id', email).maybeSingle();
  if (error || !data) return null;
  return {
    _loggedIn:  true,
    _loginEmail: email,
    restaurant: {
      name:            data.name,
      country:         data.country,
      tax:             Number(data.tax),
      tip:             Number(data.tip),
      numTables:       data.num_tables,
      address:         data.address || '',
      paymentAccounts: _j(data.payment_accounts),
      dlocalUrl:       data.dlocal_url || '',
    },
    menu:            _j(data.menu),
    tables:          _j(data.tables_data),
    nextMenuId:      data.next_menu_id,
    nextSessionId:   data.next_session_id,
  };
}

// ── SESIONES ───────────────────────────────────────────────────

async function sbUpsertSession(restaurantEmail, session) {
  const { error } = await _sb.from('sg_sessions').upsert({
    id:               String(session.id),
    restaurant_id:    restaurantEmail,
    table_number:     session.tableNumber,
    table_id:         String(session.tableId),
    join_code:        session.joinCode,
    status:           session.status,
    split_mode:       session.splitMode || 'by_item',
    tax:              session.tax,
    tip:              session.tip,
    participants:     session.participants     || [],
    orders:           session.orders           || [],
    payments:         session.payments         || [],
    transferred_debts: session.transferredDebts || [],
    opened_at:        session.openedAt,
    closed_at:        session.closedAt || null,
  }, { onConflict: 'id' });
  if (error) console.warn('sbUpsertSession:', error.message);
}

async function sbUpdateSessionFields(sessionId, fields) {
  const row = {};
  if (fields.participants     !== undefined) row.participants      = fields.participants;
  if (fields.orders           !== undefined) row.orders            = fields.orders;
  if (fields.payments         !== undefined) row.payments          = fields.payments;
  if (fields.transferredDebts !== undefined) row.transferred_debts = fields.transferredDebts;
  if (fields.status           !== undefined) row.status            = fields.status;
  if (fields.closedAt         !== undefined) row.closed_at         = fields.closedAt;
  const { error } = await _sb.from('sg_sessions').update(row).eq('id', String(sessionId));
  if (error) console.warn('sbUpdateSessionFields:', error.message);
  return !error;
}

async function sbLoadSessions(restaurantEmail) {
  const { data, error } = await _sb
    .from('sg_sessions')
    .select('*')
    .eq('restaurant_id', restaurantEmail)
    .in('status', ['occupied', 'paying']);
  if (error) { console.warn('sbLoadSessions:', error.message); return []; }
  return (data || []).map(_rowToSession);
}

async function sbGetSessionByCode(code) {
  const { data, error } = await _sb
    .from('sg_sessions')
    .select('*')
    .eq('join_code', code.toUpperCase())
    .in('status', ['occupied', 'paying'])
    .maybeSingle();
  if (error) {
    console.warn('sbGetSessionByCode:', error.message);
    throw new Error(error.message);
  }
  return data ? _rowToSession(data) : null;
}

async function sbGetSessionById(sessionId) {
  const { data, error } = await _sb
    .from('sg_sessions')
    .select('*')
    .eq('id', String(sessionId))
    .maybeSingle();
  if (error) { console.warn('sbGetSessionById:', error.message); return null; }
  return data ? _rowToSession(data) : null;
}

// ── HISTORIAL ──────────────────────────────────────────────────

async function sbSaveHistoryEntry(restaurantEmail, session) {
  const { error } = await _sb.from('sg_history').insert({
    restaurant_id: restaurantEmail,
    session_data:  session,
    closed_at:     session.closedAt || new Date().toISOString(),
  });
  if (error) console.warn('sbSaveHistoryEntry:', error.message);
}

async function sbLoadHistory(restaurantEmail) {
  const { data, error } = await _sb
    .from('sg_history')
    .select('session_data')
    .eq('restaurant_id', restaurantEmail)
    .order('closed_at', { ascending: false })
    .limit(200);
  if (error) { console.warn('sbLoadHistory:', error.message); return []; }
  return (data || []).map(r => r.session_data);
}

// ── SYNC COMPLETO (llamado desde saveRestDB) ───────────────────

let _syncPending = false;

async function sbSyncDB(db) {
  if (!db?._loginEmail || _syncPending) return;
  _syncPending = true;
  try {
    await sbSaveRestaurant(db);
    await Promise.all(db.sessions.map(s => sbUpsertSession(db._loginEmail, s)));
  } catch(e) { console.warn('sbSyncDB error:', e); }
  finally { _syncPending = false; }
}

// ── CARGA COMPLETA DESDE SUPABASE ──────────────────────────────

async function sbLoadFullDB(email) {
  try {
    const [restData, sessions, history] = await Promise.all([
      sbLoadRestaurant(email),
      sbLoadSessions(email),
      sbLoadHistory(email),
    ]);
    if (!restData) return null;
    return { ...restData, sessions, history, _loggedIn: true, _loginEmail: email };
  } catch(e) { console.warn('sbLoadFullDB error:', e); return null; }
}

// ── REALTIME ───────────────────────────────────────────────────

const _sbCh = {};

function sbSubscribeRestaurant(restaurantEmail, onChange) {
  const key = 'rest_' + restaurantEmail;
  if (_sbCh[key]) _sb.removeChannel(_sbCh[key]);
  _sbCh[key] = _sb
    .channel(key)
    .on('postgres_changes', {
      event: '*', schema: 'public', table: 'sg_sessions',
      filter: `restaurant_id=eq.${restaurantEmail}`,
    }, onChange)
    .subscribe();
}

function sbSubscribeSession(sessionId, onChange) {
  const key = 'sess_' + sessionId;
  if (_sbCh[key]) _sb.removeChannel(_sbCh[key]);
  _sbCh[key] = _sb
    .channel(key)
    .on('postgres_changes', {
      event: 'UPDATE', schema: 'public', table: 'sg_sessions',
      filter: `id=eq.${sessionId}`,
    }, onChange)
    .subscribe();
}

function sbUnsubscribeAll() {
  Object.values(_sbCh).forEach(ch => _sb.removeChannel(ch));
  Object.keys(_sbCh).forEach(k => delete _sbCh[k]);
}

// ── DIAGNÓSTICO DE SETUP ────────────────────────────────────────

// Verifica que las tablas Supabase existen y son accesibles.
// Retorna null si todo está bien, o el mensaje de error si algo falla.
async function sbCheckSetup() {
  try {
    const { error } = await _sb.from('sg_restaurants').select('id').limit(1);
    if (error) return error.message;
    return null;
  } catch(e) {
    return e.message;
  }
}
