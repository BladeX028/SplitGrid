-- ================================================================
--  SplitGrid · PostgreSQL Schema
--  Versión: 2.0  (adaptado al modelo de datos real de la aplicación)
--
--  La app usa dos capas:
--    · Tablas sg_* (JSONB) → usadas hoy en Supabase (ver supabase-migration.sql)
--    · Tablas normalizadas  → referencia de diseño / migraciones futuras
-- ================================================================


-- ─────────────────────────────────────────
-- TIPOS ENUM  (solo los que usa la app)
-- ─────────────────────────────────────────

-- Estado de mesa / sesión
CREATE TYPE table_status   AS ENUM ('free', 'occupied', 'paying', 'closed');

-- Tipo de pedido
CREATE TYPE order_type     AS ENUM ('individual', 'shared');

-- Estado de pago — únicos dos valores que registra la app
CREATE TYPE payment_status AS ENUM ('paid', 'pending_cash');

-- Modo de división de cuenta
CREATE TYPE split_mode     AS ENUM ('equal', 'by_item', 'custom');

-- Divisas: una por país soportado
CREATE TYPE currency_code  AS ENUM ('COP', 'BRL', 'EUR', 'RUB');


-- ─────────────────────────────────────────
-- PAÍSES SOPORTADOS (exactamente 5)
-- ─────────────────────────────────────────

CREATE TABLE countries (
  code          CHAR(2)        PRIMARY KEY,           -- ISO 3166-1 alpha-2
  name          VARCHAR(100)   NOT NULL,
  flag_emoji    VARCHAR(10)    NOT NULL,
  currency      currency_code  NOT NULL,
  currency_sym  VARCHAR(5)     NOT NULL,
  locale        VARCHAR(10)    NOT NULL,              -- usado en toLocaleString()
  tax_pct       NUMERIC(5,2)   NOT NULL DEFAULT 0,
  tip_pct_def   NUMERIC(5,2)   NOT NULL DEFAULT 0     -- propina por defecto (0 = opcional)
);

INSERT INTO countries VALUES
  ('CO', 'Colombia', '🇨🇴', 'COP', '$',  'es-CO', 19, 10),
  ('BR', 'Brasil',   '🇧🇷', 'BRL', 'R$', 'pt-BR',  0, 10),
  ('FR', 'France',   '🇫🇷', 'EUR', '€',  'fr-FR', 20,  0),
  ('IT', 'Italia',   '🇮🇹', 'EUR', '€',  'it-IT', 22,  0),
  ('RU', 'Россия',   '🇷🇺', 'RUB', '₽',  'ru-RU', 20,  0);

-- Métodos de pago por país (nombres y emojis exactos mostrados en la app)
CREATE TABLE country_payment_methods (
  country_code  CHAR(2)        NOT NULL REFERENCES countries(code) ON DELETE CASCADE,
  sort_order    SMALLINT       NOT NULL DEFAULT 0,
  icon          VARCHAR(10)    NOT NULL,
  name          VARCHAR(50)    NOT NULL,              -- nombre exacto tal como aparece en la app
  sub           VARCHAR(100)   NOT NULL,              -- subtítulo descriptivo
  PRIMARY KEY (country_code, name)
);

INSERT INTO country_payment_methods (country_code, sort_order, icon, name, sub) VALUES
  ('CO', 1, '💙', 'Nequi',              'Código QR / número'),
  ('CO', 2, '💚', 'Daviplata',          'Pago móvil'),
  ('CO', 3, '🔐', 'Llave Bancolombia',  'App Bancolombia'),
  ('CO', 4, '🏦', 'PSE',               'Débito bancario'),
  ('CO', 5, '💳', 'Tarjeta',            'Débito / Crédito'),
  ('CO', 6, '💵', 'Efectivo',           'Pago en caja'),
  ('BR', 1, '🟩', 'PIX',         'Pagamento instantâneo'),
  ('BR', 2, '📄', 'Boleto',      'Boleto bancário'),
  ('BR', 3, '💳', 'Cartão',      'Crédito / débito'),
  ('FR', 1, '💳', 'Carte Bleue', 'Paiement sécurisé'),
  ('FR', 2, '🍎', 'Apple Pay',   'Paiement mobile'),
  ('FR', 3, '🔵', 'Google Pay',  'Paiement mobile'),
  ('FR', 4, '🏦', 'Virement',    'Virement bancaire'),
  ('IT', 1, '💳', 'Carta',       'Credito / debito'),
  ('IT', 2, '🏦', 'Bonifico',    'Bonifico bancario'),
  ('IT', 3, '🍎', 'Apple Pay',   'Pagamento mobile'),
  ('IT', 4, '🔵', 'Satispay',    'App di pagamento'),
  ('RU', 1, '⚡', 'СБП',         'Система быстрых платежей'),
  ('RU', 2, '💳', 'Мир',         'Национальная карта'),
  ('RU', 3, '💳', 'YooMoney',    'Электронный кошелёк');


-- ─────────────────────────────────────────
-- USUARIOS
-- ─────────────────────────────────────────
-- El ID lo genera el cliente con este patrón:
--   'user_<timestamp>'   → usuario registrado con nombre
--   'guest_<timestamp>'  → invitado anónimo
--   'google_<timestamp>' → autenticado con Google (futuro)
--   'proxy_<timestamp>'  → creado por otro participante (addClientProxy)

CREATE TABLE users (
  id              TEXT           PRIMARY KEY,         -- string generado en cliente
  display_name    VARCHAR(100)   NOT NULL,
  email           VARCHAR(255),                        -- NULL si es guest o proxy
  avatar_initials VARCHAR(3),
  avatar_color    VARCHAR(120),                        -- CSS gradient, e.g. 'linear-gradient(...)'
  country_code    CHAR(2)        REFERENCES countries(code),
  is_guest        BOOLEAN        NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;


-- ─────────────────────────────────────────
-- RESTAURANTES
-- ─────────────────────────────────────────
-- El PK es el email del dueño (igual que en sg_restaurants de Supabase)
-- No existe slug, phone, logo_url ni tabla de staff en la app actual

CREATE TABLE restaurants (
  id              TEXT           PRIMARY KEY,         -- email del dueño
  name            VARCHAR(150)   NOT NULL DEFAULT 'Mi Restaurante',
  country_code    CHAR(2)        NOT NULL REFERENCES countries(code) DEFAULT 'CO',
  address         TEXT           NOT NULL DEFAULT '',
  tax_pct         NUMERIC(5,2)   NOT NULL DEFAULT 19,
  tip_pct_default NUMERIC(5,2)   NOT NULL DEFAULT 10,
  num_tables      SMALLINT       NOT NULL DEFAULT 10,
  next_menu_id    INT            NOT NULL DEFAULT 1,  -- contador para IDs de ítems del menú
  next_session_id INT            NOT NULL DEFAULT 1,  -- contador para IDs de sesiones
  updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_restaurants_country ON restaurants(country_code);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$;

CREATE TRIGGER trg_restaurants_updated_at
  BEFORE UPDATE ON restaurants
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ─────────────────────────────────────────
-- MESAS
-- ─────────────────────────────────────────

CREATE TABLE tables (
  id              TEXT           PRIMARY KEY,         -- '1', '2', ... (número como string)
  restaurant_id   TEXT           NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  number          SMALLINT       NOT NULL,
  status          table_status   NOT NULL DEFAULT 'free',
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  UNIQUE(restaurant_id, number)
);

CREATE INDEX idx_tables_restaurant ON tables(restaurant_id);
CREATE INDEX idx_tables_status     ON tables(restaurant_id, status);


-- ─────────────────────────────────────────
-- MENÚ
-- ─────────────────────────────────────────
-- NO existe tabla de categorías: la categoría es un campo TEXT libre en cada ítem
-- (ej. '🍛 Platos Fuertes', '🥗 Entradas', '🥤 Bebidas')
-- El IVA está incluido en el precio (price = precio final al cliente)

CREATE TABLE menu_items (
  id              INT            NOT NULL,             -- entero local (restaurants.next_menu_id)
  restaurant_id   TEXT           NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name            VARCHAR(150)   NOT NULL,
  emoji           VARCHAR(10)    NOT NULL DEFAULT '',
  cat             VARCHAR(80)    NOT NULL DEFAULT '',  -- categoría libre, ej. '🍛 Platos Fuertes'
  price           NUMERIC(12,2)  NOT NULL,             -- precio con IVA incluido
  is_available    BOOLEAN        NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  PRIMARY KEY (restaurant_id, id)                      -- PK compuesta: email + int
);

CREATE INDEX idx_menu_items_restaurant ON menu_items(restaurant_id);
CREATE INDEX idx_menu_items_available  ON menu_items(restaurant_id, is_available);

CREATE TRIGGER trg_menu_items_updated_at
  BEFORE UPDATE ON menu_items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ─────────────────────────────────────────
-- SESIONES DE MESA
-- ─────────────────────────────────────────
-- El ID es un entero representado como string (restaurants.next_session_id)
-- tax y tip son porcentajes snapshot tomados al abrir la sesión

CREATE TABLE sessions (
  id              TEXT           PRIMARY KEY,         -- entero como string, ej. '1', '42'
  restaurant_id   TEXT           NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  table_number    INT            NOT NULL,
  table_id        TEXT           NOT NULL REFERENCES tables(id),
  join_code       CHAR(6)        NOT NULL,
  status          table_status   NOT NULL DEFAULT 'occupied',
  split_mode      split_mode     NOT NULL DEFAULT 'by_item',
  tax             NUMERIC(5,2)   NOT NULL DEFAULT 0,  -- % IVA (snapshot)
  tip             NUMERIC(5,2)   NOT NULL DEFAULT 0,  -- % propina elegida (0 = sin propina)
  opened_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  closed_at       TIMESTAMPTZ
);

-- Solo un código activo a la vez
CREATE UNIQUE INDEX idx_sessions_active_code
  ON sessions(join_code)
  WHERE status IN ('occupied', 'paying');

CREATE INDEX idx_sessions_restaurant ON sessions(restaurant_id);
CREATE INDEX idx_sessions_table      ON sessions(table_id);
CREATE INDEX idx_sessions_status     ON sessions(status);


-- ─────────────────────────────────────────
-- PARTICIPANTES DE SESIÓN
-- ─────────────────────────────────────────
-- is_proxy=true → fue creado por otro participante con "Agregar para mí"
-- managed_by    → id del participante real que gestiona este proxy

CREATE TABLE session_participants (
  id              TEXT           NOT NULL,             -- 'user_ts', 'guest_ts', 'proxy_ts'
  session_id      TEXT           NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  name            VARCHAR(100)   NOT NULL,
  color           VARCHAR(120)   NOT NULL DEFAULT '', -- CSS gradient para el avatar
  is_proxy        BOOLEAN        NOT NULL DEFAULT false,
  managed_by      TEXT,                               -- id del participante gestor (si is_proxy)
  joined_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  PRIMARY KEY (session_id, id)
);

CREATE INDEX idx_participants_session ON session_participants(session_id);


-- ─────────────────────────────────────────
-- PEDIDOS
-- ─────────────────────────────────────────
-- unit_price es snapshot del precio al momento del pedido
-- shared_with puede ser:
--   · JSONB array de TEXT IDs  → ['user_123','proxy_456']
--   · JSONB number             → cantidad de personas que comparten
--   · NULL                     → todos los participantes de la sesión

CREATE TABLE orders (
  id              BIGSERIAL      PRIMARY KEY,
  session_id      TEXT           NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  restaurant_id   TEXT           NOT NULL,             -- necesario para FK compuesta con menu_items
  menu_item_id    INT            NOT NULL,
  qty             SMALLINT       NOT NULL DEFAULT 1,
  unit_price      NUMERIC(12,2)  NOT NULL,             -- snapshot del precio al pedir
  order_type      order_type     NOT NULL DEFAULT 'individual',
  -- Solo para type='individual':
  person_id       TEXT,                               -- id del participante
  person_name     TEXT,                               -- snapshot del nombre
  -- Solo para type='shared':
  shared_with     JSONB,                              -- ver comentario arriba
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  FOREIGN KEY (restaurant_id, menu_item_id) REFERENCES menu_items(restaurant_id, id)
);

CREATE INDEX idx_orders_session ON orders(session_id);
CREATE INDEX idx_orders_person  ON orders(session_id, person_id);


-- ─────────────────────────────────────────
-- PAGOS
-- ─────────────────────────────────────────
-- base_amount   = subtotal de los ítems del participante
-- tip_amount    = monto de propina (0 si tip_included=false)
-- amount        = base_amount + tip_amount (si tip_included) o solo base_amount
-- method        = texto libre que coincide con country_payment_methods.name

CREATE TABLE payments (
  id              BIGSERIAL      PRIMARY KEY,
  session_id      TEXT           NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  person_id       TEXT           NOT NULL,             -- id del participante
  person_name     TEXT           NOT NULL,             -- snapshot del nombre
  base_amount     NUMERIC(14,2)  NOT NULL,             -- subtotal de ítems
  tip_pct         NUMERIC(5,2)   NOT NULL DEFAULT 0,   -- porcentaje de propina ofrecido
  tip_amount      NUMERIC(14,2)  NOT NULL DEFAULT 0,   -- monto de propina
  tip_included    BOOLEAN        NOT NULL DEFAULT false,-- el cliente decidió incluir propina
  amount          NUMERIC(14,2)  NOT NULL,             -- total desembolsado
  method          TEXT           NOT NULL,             -- ej. 'Nequi', 'PIX', 'Carte Bleue'
  status          payment_status NOT NULL DEFAULT 'paid',
  paid_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  confirmed_at    TIMESTAMPTZ,                         -- cuándo el restaurante confirmó el pago
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payments_session ON payments(session_id);
CREATE INDEX idx_payments_person  ON payments(session_id, person_id);
CREATE INDEX idx_payments_status  ON payments(status);


-- ─────────────────────────────────────────
-- DEUDAS TRANSFERIDAS
-- ─────────────────────────────────────────
-- Cuando el restaurante elimina un participante de la sesión,
-- su deuda pendiente se redistribuye a los demás y queda registrada aquí.

CREATE TABLE transferred_debts (
  id              BIGSERIAL      PRIMARY KEY,
  session_id      TEXT           NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  from_person_id  TEXT           NOT NULL,             -- participante eliminado
  from_person_name TEXT          NOT NULL,             -- snapshot del nombre
  to_person_id    TEXT           NOT NULL,             -- quien asume la deuda
  amount          NUMERIC(14,2)  NOT NULL,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_debts_session   ON transferred_debts(session_id);
CREATE INDEX idx_debts_to_person ON transferred_debts(session_id, to_person_id);


-- ─────────────────────────────────────────
-- HISTORIAL DE SESIONES CERRADAS
-- ─────────────────────────────────────────

CREATE TABLE history (
  id              BIGSERIAL    PRIMARY KEY,
  restaurant_id   TEXT         NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  session_data    JSONB        NOT NULL,               -- snapshot completo del objeto session
  closed_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_history_restaurant ON history(restaurant_id);
CREATE INDEX idx_history_closed_at  ON history(restaurant_id, closed_at DESC);


-- ─────────────────────────────────────────
-- HISTORIAL DE PAGOS DEL CLIENTE
-- ─────────────────────────────────────────
-- Espejo del array CL.payments almacenado en localStorage del cliente.
-- Se puede poblar si se implementa sync del lado del cliente en el futuro.

CREATE TABLE client_payment_history (
  id              BIGSERIAL      PRIMARY KEY,
  person_id       TEXT           NOT NULL,             -- ID local del cliente
  session_id      TEXT           NOT NULL,             -- referencia informativa (no FK)
  restaurant_name TEXT           NOT NULL,
  table_number    INT            NOT NULL,
  amount          NUMERIC(14,2)  NOT NULL,
  base_amount     NUMERIC(14,2)  NOT NULL,
  tip_amount      NUMERIC(14,2)  NOT NULL DEFAULT 0,
  method          TEXT           NOT NULL,
  status          payment_status NOT NULL DEFAULT 'paid',
  paid_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_client_history_person ON client_payment_history(person_id);


-- ================================================================
--  TABLAS sg_* — LAS QUE USA HOY LA APP EN SUPABASE
--  (versión JSONB, definidas también en supabase-migration.sql)
-- ================================================================

CREATE TABLE IF NOT EXISTS sg_restaurants (
  id              TEXT          PRIMARY KEY,           -- email del dueño
  name            TEXT          NOT NULL DEFAULT 'Mi Restaurante',
  country         TEXT          NOT NULL DEFAULT 'CO',
  tax             NUMERIC(5,2)  NOT NULL DEFAULT 19,
  tip             NUMERIC(5,2)  NOT NULL DEFAULT 10,
  num_tables      INT           NOT NULL DEFAULT 10,
  address         TEXT          NOT NULL DEFAULT '',
  -- Arreglo JSON de ítems: [{id, name, emoji, cat, price, is_available}]
  menu            JSONB         NOT NULL DEFAULT '[]'::jsonb,
  -- Arreglo JSON de mesas: [{id, number, status}]
  tables_data     JSONB         NOT NULL DEFAULT '[]'::jsonb,
  next_menu_id    INT           NOT NULL DEFAULT 1,
  next_session_id INT           NOT NULL DEFAULT 1,
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sg_sessions (
  id                TEXT         PRIMARY KEY,          -- entero como string
  restaurant_id     TEXT         NOT NULL REFERENCES sg_restaurants(id) ON DELETE CASCADE,
  table_number      INT          NOT NULL,
  table_id          TEXT,
  join_code         TEXT         NOT NULL,
  status            TEXT         NOT NULL DEFAULT 'occupied', -- 'occupied' | 'paying' | 'closed'
  split_mode        TEXT         NOT NULL DEFAULT 'by_item',  -- 'equal' | 'by_item' | 'custom'
  tax               NUMERIC(5,2) NOT NULL DEFAULT 0,
  tip               NUMERIC(5,2) NOT NULL DEFAULT 0,
  -- [{id, name, color, isProxy?, managedBy?}]
  participants      JSONB        NOT NULL DEFAULT '[]'::jsonb,
  -- [{id, menuItemId, qty, type, personId?, personName?, sharedWith?}]
  orders            JSONB        NOT NULL DEFAULT '[]'::jsonb,
  -- [{personId, amount, baseAmount, tipAmount, tipPct, tipIncluded, method, status, ref, paidAt, confirmedAt?}]
  payments          JSONB        NOT NULL DEFAULT '[]'::jsonb,
  -- [{fromPersonId, fromPersonName, toPersonId, amount}]
  transferred_debts JSONB        NOT NULL DEFAULT '[]'::jsonb,
  opened_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  closed_at         TIMESTAMPTZ
);

-- Solo un código de unión activo por vez
CREATE UNIQUE INDEX IF NOT EXISTS sg_sessions_active_code
  ON sg_sessions(join_code)
  WHERE status IN ('occupied', 'paying');

CREATE TABLE IF NOT EXISTS sg_history (
  id              BIGSERIAL    PRIMARY KEY,
  restaurant_id   TEXT         NOT NULL REFERENCES sg_restaurants(id) ON DELETE CASCADE,
  session_data    JSONB        NOT NULL,
  closed_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- RLS desactivado para prototipo (activar con políticas antes de producción)
ALTER TABLE sg_restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE sg_sessions    DISABLE ROW LEVEL SECURITY;
ALTER TABLE sg_history     DISABLE ROW LEVEL SECURITY;

-- Habilitar Realtime para que el cliente reciba actualizaciones en tiempo real
ALTER PUBLICATION supabase_realtime ADD TABLE sg_sessions;


-- ─────────────────────────────────────────
-- VISTAS ÚTILES
-- ─────────────────────────────────────────

-- Resumen por sesión activa (normalizado)
CREATE OR REPLACE VIEW v_session_summary AS
SELECT
  s.id                                    AS session_id,
  s.join_code,
  s.status,
  s.split_mode,
  s.tax,
  s.tip,
  s.table_number,
  s.opened_at,
  r.id                                    AS restaurant_id,
  r.name                                  AS restaurant_name,
  c.code                                  AS country_code,
  c.flag_emoji,
  c.currency::TEXT                        AS currency,
  c.currency_sym,
  c.locale,
  COUNT(DISTINCT p.id)                    AS participant_count,
  COALESCE(SUM(o.unit_price * o.qty), 0) AS subtotal,
  -- NOTA: tip_amount aquí es estimado máximo (subtotal × tip%). En la app,
  -- la propina aplica solo al saldo pendiente de cada cliente (no al total).
  COALESCE(SUM(o.unit_price * o.qty), 0) * s.tip / 100 AS estimated_tip_max
FROM sessions s
JOIN restaurants r ON r.id = s.restaurant_id
JOIN countries   c ON c.code = r.country_code
LEFT JOIN session_participants p ON p.session_id = s.id
LEFT JOIN orders o               ON o.session_id = s.id
GROUP BY s.id, r.id, c.code;

-- Cuánto debe pagar cada participante (modo by_item)
CREATE OR REPLACE VIEW v_participant_totals AS
SELECT
  sp.session_id,
  sp.id                                   AS person_id,
  sp.name                                 AS display_name,
  sp.color                                AS avatar_color,
  sp.is_proxy,
  -- Ítems individuales propios
  COALESCE(SUM(
    CASE WHEN o.order_type = 'individual' AND o.person_id = sp.id
         THEN o.unit_price * o.qty ELSE 0 END
  ), 0)                                   AS own_items_total,
  -- Parte de ítems compartidos (división igualitaria)
  COALESCE(SUM(
    CASE WHEN o.order_type = 'shared' THEN
      o.unit_price * o.qty / NULLIF(
        CASE
          WHEN o.shared_with IS NULL THEN
            (SELECT COUNT(*) FROM session_participants sp2
             WHERE sp2.session_id = sp.session_id)
          WHEN jsonb_typeof(o.shared_with) = 'number' THEN
            (o.shared_with #>> '{}')::NUMERIC
          ELSE
            jsonb_array_length(o.shared_with)
        END, 0)
    ELSE 0 END
  ), 0)                                   AS shared_items_total,
  -- Deudas transferidas a este participante
  COALESCE((
    SELECT SUM(td.amount) FROM transferred_debts td
    WHERE td.session_id = sp.session_id AND td.to_person_id = sp.id
  ), 0)                                   AS transferred_debt,
  -- Monto ya pagado
  COALESCE((
    SELECT SUM(py.amount) FROM payments py
    WHERE py.session_id = sp.session_id
      AND py.person_id = sp.id
      AND py.status = 'paid'
  ), 0)                                   AS paid_amount
FROM session_participants sp
LEFT JOIN orders o ON o.session_id = sp.session_id
GROUP BY sp.session_id, sp.id, sp.name, sp.color, sp.is_proxy;

-- Historial de pagos del cliente con contexto de sesión
CREATE OR REPLACE VIEW v_payment_history AS
SELECT
  py.id                                   AS payment_id,
  py.person_id,
  py.person_name,
  py.amount,
  py.base_amount,
  py.tip_amount,
  py.method,
  py.status,
  py.paid_at,
  s.join_code,
  s.table_number,
  r.name                                  AS restaurant_name,
  c.flag_emoji,
  c.currency_sym,
  c.locale,
  COUNT(DISTINCT sp2.id)                  AS table_participants
FROM payments py
JOIN sessions s            ON s.id = py.session_id
JOIN restaurants r         ON r.id = s.restaurant_id
JOIN countries c           ON c.code = r.country_code
LEFT JOIN session_participants sp2 ON sp2.session_id = s.id
GROUP BY py.id, s.id, r.id, c.code;


-- ─────────────────────────────────────────
-- FUNCIÓN: GENERAR CÓDIGO ÚNICO DE 6 CHARS
-- ─────────────────────────────────────────
-- Mismo alfabeto que genCode() en shared.js: sin I, O, 0, 1

CREATE OR REPLACE FUNCTION generate_join_code()
RETURNS CHAR(6) LANGUAGE plpgsql AS $$
DECLARE
  chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code  CHAR(6);
  tries INT := 0;
BEGIN
  LOOP
    code := '';
    FOR i IN 1..6 LOOP
      code := code || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM sg_sessions
      WHERE join_code = code AND status IN ('occupied', 'paying')
    );
    tries := tries + 1;
    IF tries > 100 THEN
      RAISE EXCEPTION 'No se pudo generar código de unión único después de 100 intentos';
    END IF;
  END LOOP;
  RETURN code;
END; $$;


-- ─────────────────────────────────────────
-- DATOS DE EJEMPLO
-- ─────────────────────────────────────────
-- Refleja el buildDefaultRestDB() del restaurante demo:
--   · Restaurante colombiano, 10 mesas, IVA 19%, propina 10%
--   · 7 ítems de menú (nextMenuId = 8)

INSERT INTO sg_restaurants (
  id, name, country, tax, tip, num_tables, address,
  next_menu_id, next_session_id, menu, tables_data
) VALUES (
  'demo@rinconcriollo.co',
  'El Rincón Criollo',
  'CO',
  19,
  10,
  10,
  'Cra 7 #45-23, Bogotá',
  8,   -- 7 ítems creados, el siguiente sería id=8
  1,
  '[
    {"id":1,"name":"Bandeja Paisa",       "emoji":"🍛","cat":"🍛 Platos Fuertes","price":42000,"is_available":true},
    {"id":2,"name":"Ajiaco Bogotano",     "emoji":"🍜","cat":"🍛 Platos Fuertes","price":35000,"is_available":true},
    {"id":3,"name":"Picada Mixta",        "emoji":"🥩","cat":"🍛 Platos Fuertes","price":74000,"is_available":true},
    {"id":4,"name":"Cazuela de Mariscos", "emoji":"🦐","cat":"🍛 Platos Fuertes","price":58000,"is_available":true},
    {"id":5,"name":"Ensalada Caesar",     "emoji":"🥗","cat":"🥗 Entradas",      "price":22000,"is_available":true},
    {"id":6,"name":"Patacones",           "emoji":"🍟","cat":"🥗 Entradas",      "price":12000,"is_available":true},
    {"id":7,"name":"Limonada de Coco",    "emoji":"🥥","cat":"🥤 Bebidas",       "price":12000,"is_available":true}
  ]'::jsonb,
  '[
    {"id":"1", "number":1,  "status":"free"},
    {"id":"2", "number":2,  "status":"free"},
    {"id":"3", "number":3,  "status":"free"},
    {"id":"4", "number":4,  "status":"free"},
    {"id":"5", "number":5,  "status":"free"},
    {"id":"6", "number":6,  "status":"free"},
    {"id":"7", "number":7,  "status":"free"},
    {"id":"8", "number":8,  "status":"free"},
    {"id":"9", "number":9,  "status":"free"},
    {"id":"10","number":10, "status":"free"}
  ]'::jsonb
);
