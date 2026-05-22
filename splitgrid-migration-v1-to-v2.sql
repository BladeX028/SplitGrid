-- ================================================================
--  SplitGrid · Migración v1.0 → v2.0
--  Ejecutar en: Dashboard → SQL Editor
--  https://supabase.com/dashboard/project/jqwgmxavuvaklbszmfkp/editor
--
--  IMPORTANTE: Este script asume que ya existe el schema v1.0
--  (countries, users, restaurants, tables, menu_items, sessions,
--   session_participants, orders, payments, etc. con IDs UUID).
--
--  Los cambios principales:
--    · IDs de UUID → TEXT  (el email es PK de restaurante)
--    · Se eliminan tablas no usadas: restaurant_staff, menu_categories, order_participants
--    · Se corrigen enums: payment_status, currency_code; se elimina user_role, order_status, payment_method
--    · Países: de 9 a 5; se agrega columna locale
--    · menu_items: PK compuesta (restaurant_id, id INT); se agrega cat TEXT
--    · sessions: se agrega table_number; tax_pct/tip_pct → tax/tip
--    · session_participants: se agrega is_proxy, managed_by; display_name → name
--    · orders: quantity → qty; se elimina status, notes, total_price; se agregan person_name, shared_with JSONB
--    · payments: se agregan base_amount, tip_pct, tip_included, confirmed_at; se elimina tax_amount, gateway_ref, rating
--    · Nuevas tablas: transferred_debts, history, client_payment_history
--    · Nuevas tablas sg_* (las que usa la app en Supabase hoy)
-- ================================================================

BEGIN;

-- ─────────────────────────────────────────
-- PASO 1: Eliminar vistas y funciones que dependen de las tablas
-- ─────────────────────────────────────────

DROP VIEW     IF EXISTS v_payment_history    CASCADE;
DROP VIEW     IF EXISTS v_participant_totals CASCADE;
DROP VIEW     IF EXISTS v_session_summary    CASCADE;

DROP FUNCTION IF EXISTS register_payment(UUID, UUID, NUMERIC, payment_method) CASCADE;
DROP FUNCTION IF EXISTS join_session(CHAR, UUID, VARCHAR)                     CASCADE;
DROP FUNCTION IF EXISTS open_session(UUID, UUID, split_mode)                  CASCADE;
DROP FUNCTION IF EXISTS generate_join_code()                                  CASCADE;

-- ─────────────────────────────────────────
-- PASO 2: Eliminar tablas que ya no existen en la app
-- ─────────────────────────────────────────

DROP TABLE IF EXISTS order_participants CASCADE;  -- reemplazado por orders.shared_with JSONB
DROP TABLE IF EXISTS restaurant_staff   CASCADE;  -- no existe en la app
DROP TABLE IF EXISTS menu_categories    CASCADE;  -- reemplazado por menu_items.cat TEXT

-- ─────────────────────────────────────────
-- PASO 3: Cambios en ENUMs
-- ─────────────────────────────────────────

-- 3a. Eliminar tipos que ya no usa la app
DROP TYPE IF EXISTS user_role    CASCADE;
DROP TYPE IF EXISTS order_status CASCADE;

-- 3b. payment_method: la app usa TEXT libre, no un enum
--     (los métodos se llaman 'Nequi', 'PIX', 'Carte Bleue', etc.)
--     Primero cambiamos la columna de payments a TEXT, luego borramos el tipo
ALTER TABLE payments
  ALTER COLUMN method TYPE TEXT USING method::TEXT;

DROP TYPE IF EXISTS payment_method CASCADE;

-- 3c. payment_status: solo 'paid' y 'pending_cash'
--     PostgreSQL no permite eliminar valores de un enum, hay que recrearlo.
--     Primero se quita el DEFAULT para que no bloquee el cambio de tipo.
ALTER TABLE payments ALTER COLUMN status DROP DEFAULT;

ALTER TYPE payment_status RENAME TO _payment_status_old;
CREATE TYPE payment_status AS ENUM ('paid', 'pending_cash');

ALTER TABLE payments
  ALTER COLUMN status TYPE payment_status
  USING CASE
    WHEN status::TEXT = 'paid'    THEN 'paid'::payment_status
    ELSE 'pending_cash'::payment_status
  END;

DROP TYPE _payment_status_old;

-- 3d. currency_code: solo COP, BRL, EUR, RUB  (se eliminan USD, MXN, ARS, PEN, CLP)
--     Primero aseguramos que no haya filas con esas monedas
DELETE FROM countries WHERE code NOT IN ('CO', 'BR', 'FR', 'IT', 'RU');

ALTER TYPE currency_code RENAME TO _currency_code_old;
CREATE TYPE currency_code AS ENUM ('COP', 'BRL', 'EUR', 'RUB');

ALTER TABLE countries
  ALTER COLUMN currency TYPE currency_code
  USING currency::TEXT::currency_code;

DROP TYPE _currency_code_old;

-- ─────────────────────────────────────────
-- PASO 4: Tabla countries
-- ─────────────────────────────────────────

-- 4a. Eliminar columna payment_methods (era un array del enum ya borrado)
ALTER TABLE countries DROP COLUMN IF EXISTS payment_methods;

-- 4b. Agregar columna locale
ALTER TABLE countries ADD COLUMN IF NOT EXISTS locale VARCHAR(10);

UPDATE countries SET locale = 'es-CO' WHERE code = 'CO';
UPDATE countries SET locale = 'pt-BR' WHERE code = 'BR';
UPDATE countries SET locale = 'fr-FR' WHERE code = 'FR';
UPDATE countries SET locale = 'it-IT' WHERE code = 'IT';
UPDATE countries SET locale = 'ru-RU' WHERE code = 'RU';

ALTER TABLE countries ALTER COLUMN locale SET NOT NULL;

-- 4c. Corregir nombres
UPDATE countries SET name = 'France'  WHERE code = 'FR';
UPDATE countries SET name = 'Italia'  WHERE code = 'IT';
UPDATE countries SET name = 'Россия'  WHERE code = 'RU';

-- 4d. Agregar país IT si no existía (el v1.0 no lo tenía)
INSERT INTO countries (code, name, flag_emoji, currency, currency_sym, locale, tax_pct, tip_pct_def)
VALUES ('IT', 'Italia', '🇮🇹', 'EUR', '€', 'it-IT', 22, 0)
ON CONFLICT (code) DO NOTHING;

-- 4e. Crear tabla de métodos de pago por país
CREATE TABLE IF NOT EXISTS country_payment_methods (
  country_code  CHAR(2)      NOT NULL REFERENCES countries(code) ON DELETE CASCADE,
  sort_order    SMALLINT     NOT NULL DEFAULT 0,
  icon          VARCHAR(10)  NOT NULL,
  name          VARCHAR(50)  NOT NULL,
  sub           VARCHAR(100) NOT NULL,
  PRIMARY KEY (country_code, name)
);

INSERT INTO country_payment_methods (country_code, sort_order, icon, name, sub) VALUES
  ('CO',1,'💙','Nequi',       'Pago instantáneo'),
  ('CO',2,'💚','Daviplata',   'Pago móvil'),
  ('CO',3,'🏦','PSE',         'Débito bancario'),
  ('CO',4,'💳','Tarjeta',     'Visa, Mastercard'),
  ('CO',5,'💵','Efectivo',    'Punto físico'),
  ('BR',1,'🟩','PIX',         'Pagamento instantâneo'),
  ('BR',2,'📄','Boleto',      'Boleto bancário'),
  ('BR',3,'💳','Cartão',      'Crédito / débito'),
  ('FR',1,'💳','Carte Bleue', 'Paiement sécurisé'),
  ('FR',2,'🍎','Apple Pay',   'Paiement mobile'),
  ('FR',3,'🔵','Google Pay',  'Paiement mobile'),
  ('FR',4,'🏦','Virement',    'Virement bancaire'),
  ('IT',1,'💳','Carta',       'Credito / debito'),
  ('IT',2,'🏦','Bonifico',    'Bonifico bancario'),
  ('IT',3,'🍎','Apple Pay',   'Pagamento mobile'),
  ('IT',4,'🔵','Satispay',    'App di pagamento'),
  ('RU',1,'⚡','СБП',         'Система быстрых платежей'),
  ('RU',2,'💳','Мир',         'Национальная карта'),
  ('RU',3,'💳','YooMoney',    'Электронный кошелёк')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────
-- PASO 5: Tablas con UUID → TEXT
-- (La forma más segura en Postgres es DROP CASCADE + recrear)
-- Nota: si tienes datos que quieres preservar, expórtalos antes.
-- ─────────────────────────────────────────

-- Eliminar en orden de dependencias (hijos primero)
DROP TABLE IF EXISTS payments             CASCADE;
DROP TABLE IF EXISTS orders               CASCADE;
DROP TABLE IF EXISTS session_participants CASCADE;
DROP TABLE IF EXISTS sessions             CASCADE;
DROP TABLE IF EXISTS tables               CASCADE;
DROP TABLE IF EXISTS menu_items           CASCADE;
DROP TABLE IF EXISTS restaurants          CASCADE;
DROP TABLE IF EXISTS users                CASCADE;

-- Asegurarnos que set_updated_at() sigue existiendo (puede haber quedado del v1.0)
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$;

-- ─────────────────────────────────────────
-- PASO 6: Recrear tablas con el nuevo modelo
-- ─────────────────────────────────────────

-- 6a. users  (id TEXT en lugar de UUID)
CREATE TABLE users (
  id              TEXT           PRIMARY KEY,     -- 'user_ts', 'guest_ts', 'proxy_ts'
  display_name    VARCHAR(100)   NOT NULL,
  email           VARCHAR(255),
  avatar_initials VARCHAR(3),
  avatar_color    VARCHAR(120),
  country_code    CHAR(2)        REFERENCES countries(code),
  is_guest        BOOLEAN        NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;

-- 6b. restaurants  (id = email del dueño)
CREATE TABLE restaurants (
  id              TEXT           PRIMARY KEY,
  name            VARCHAR(150)   NOT NULL DEFAULT 'Mi Restaurante',
  country_code    CHAR(2)        NOT NULL REFERENCES countries(code) DEFAULT 'CO',
  address         TEXT           NOT NULL DEFAULT '',
  tax_pct         NUMERIC(5,2)   NOT NULL DEFAULT 19,
  tip_pct_default NUMERIC(5,2)   NOT NULL DEFAULT 10,
  num_tables      SMALLINT       NOT NULL DEFAULT 10,
  next_menu_id    INT            NOT NULL DEFAULT 1,
  next_session_id INT            NOT NULL DEFAULT 1,
  updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_restaurants_country ON restaurants(country_code);
CREATE TRIGGER trg_restaurants_updated_at
  BEFORE UPDATE ON restaurants
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 6c. tables  (id TEXT: '1', '2', ...)
CREATE TABLE tables (
  id              TEXT           PRIMARY KEY,
  restaurant_id   TEXT           NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  number          SMALLINT       NOT NULL,
  status          table_status   NOT NULL DEFAULT 'free',
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  UNIQUE(restaurant_id, number)
);
CREATE INDEX idx_tables_restaurant ON tables(restaurant_id);
CREATE INDEX idx_tables_status     ON tables(restaurant_id, status);

-- 6d. menu_items  (PK compuesta: restaurant_id + id INT; cat TEXT en lugar de category_id UUID)
CREATE TABLE menu_items (
  id              INT            NOT NULL,
  restaurant_id   TEXT           NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name            VARCHAR(150)   NOT NULL,
  emoji           VARCHAR(10)    NOT NULL DEFAULT '',
  cat             VARCHAR(80)    NOT NULL DEFAULT '',   -- '🍛 Platos Fuertes', etc.
  price           NUMERIC(12,2)  NOT NULL,
  is_available    BOOLEAN        NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX idx_menu_items_restaurant ON menu_items(restaurant_id);
CREATE INDEX idx_menu_items_available  ON menu_items(restaurant_id, is_available);
CREATE TRIGGER trg_menu_items_updated_at
  BEFORE UPDATE ON menu_items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 6e. sessions  (id TEXT; tax/tip en lugar de tax_pct/tip_pct; agrega table_number)
CREATE TABLE sessions (
  id              TEXT           PRIMARY KEY,
  restaurant_id   TEXT           NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  table_number    INT            NOT NULL,
  table_id        TEXT           NOT NULL REFERENCES tables(id),
  join_code       CHAR(6)        NOT NULL,
  status          table_status   NOT NULL DEFAULT 'occupied',
  split_mode      split_mode     NOT NULL DEFAULT 'by_item',
  tax             NUMERIC(5,2)   NOT NULL DEFAULT 0,
  tip             NUMERIC(5,2)   NOT NULL DEFAULT 0,
  opened_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  closed_at       TIMESTAMPTZ
);
CREATE UNIQUE INDEX idx_sessions_active_code
  ON sessions(join_code) WHERE status IN ('occupied', 'paying');
CREATE INDEX idx_sessions_restaurant ON sessions(restaurant_id);
CREATE INDEX idx_sessions_table      ON sessions(table_id);
CREATE INDEX idx_sessions_status     ON sessions(status);

-- 6f. session_participants  (id TEXT; agrega is_proxy y managed_by; display_name → name)
CREATE TABLE session_participants (
  id              TEXT           NOT NULL,
  session_id      TEXT           NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  name            VARCHAR(100)   NOT NULL,
  color           VARCHAR(120)   NOT NULL DEFAULT '',
  is_proxy        BOOLEAN        NOT NULL DEFAULT false,
  managed_by      TEXT,
  joined_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  PRIMARY KEY (session_id, id)
);
CREATE INDEX idx_participants_session ON session_participants(session_id);

-- 6g. orders  (BIGSERIAL; quantity → qty; agrega person_name y shared_with JSONB;
--              elimina status, notes, total_price; created_by → person_id TEXT)
CREATE TABLE orders (
  id              BIGSERIAL      PRIMARY KEY,
  session_id      TEXT           NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  restaurant_id   TEXT           NOT NULL,
  menu_item_id    INT            NOT NULL,
  qty             SMALLINT       NOT NULL DEFAULT 1,
  unit_price      NUMERIC(12,2)  NOT NULL,
  order_type      order_type     NOT NULL DEFAULT 'individual',
  person_id       TEXT,
  person_name     TEXT,
  shared_with     JSONB,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  FOREIGN KEY (restaurant_id, menu_item_id) REFERENCES menu_items(restaurant_id, id)
);
CREATE INDEX idx_orders_session ON orders(session_id);
CREATE INDEX idx_orders_person  ON orders(session_id, person_id);

-- 6h. payments  (BIGSERIAL; user_id → person_id TEXT; agrega base_amount, tip_pct,
--               tip_included, confirmed_at; elimina subtotal, tax_amount, gateway_ref,
--               reference_code, rating, rating_comment)
CREATE TABLE payments (
  id              BIGSERIAL      PRIMARY KEY,
  session_id      TEXT           NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  person_id       TEXT           NOT NULL,
  person_name     TEXT           NOT NULL,
  base_amount     NUMERIC(14,2)  NOT NULL,
  tip_pct         NUMERIC(5,2)   NOT NULL DEFAULT 0,
  tip_amount      NUMERIC(14,2)  NOT NULL DEFAULT 0,
  tip_included    BOOLEAN        NOT NULL DEFAULT false,
  amount          NUMERIC(14,2)  NOT NULL,
  method          TEXT           NOT NULL,
  status          payment_status NOT NULL DEFAULT 'paid',
  paid_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  confirmed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_payments_session ON payments(session_id);
CREATE INDEX idx_payments_person  ON payments(session_id, person_id);
CREATE INDEX idx_payments_status  ON payments(status);

-- ─────────────────────────────────────────
-- PASO 7: Nuevas tablas
-- ─────────────────────────────────────────

-- 7a. transferred_debts (nueva: redistribución de deuda al eliminar participante)
CREATE TABLE IF NOT EXISTS transferred_debts (
  id               BIGSERIAL      PRIMARY KEY,
  session_id       TEXT           NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  from_person_id   TEXT           NOT NULL,
  from_person_name TEXT           NOT NULL,
  to_person_id     TEXT           NOT NULL,
  amount           NUMERIC(14,2)  NOT NULL,
  created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_debts_session   ON transferred_debts(session_id);
CREATE INDEX idx_debts_to_person ON transferred_debts(session_id, to_person_id);

-- 7b. history (renombrada desde el sg_history; versión normalizada)
CREATE TABLE IF NOT EXISTS history (
  id              BIGSERIAL    PRIMARY KEY,
  restaurant_id   TEXT         NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  session_data    JSONB        NOT NULL,
  closed_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_history_restaurant ON history(restaurant_id);
CREATE INDEX idx_history_closed_at  ON history(restaurant_id, closed_at DESC);

-- 7c. client_payment_history (espejo del CL.payments del cliente)
CREATE TABLE IF NOT EXISTS client_payment_history (
  id              BIGSERIAL      PRIMARY KEY,
  person_id       TEXT           NOT NULL,
  session_id      TEXT           NOT NULL,
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

-- ─────────────────────────────────────────
-- PASO 8: Tablas sg_* (las que usa la app hoy en Supabase)
-- ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sg_restaurants (
  id              TEXT          PRIMARY KEY,
  name            TEXT          NOT NULL DEFAULT 'Mi Restaurante',
  country         TEXT          NOT NULL DEFAULT 'CO',
  tax             NUMERIC(5,2)  NOT NULL DEFAULT 19,
  tip             NUMERIC(5,2)  NOT NULL DEFAULT 10,
  num_tables      INT           NOT NULL DEFAULT 10,
  address         TEXT          NOT NULL DEFAULT '',
  menu            JSONB         NOT NULL DEFAULT '[]'::jsonb,
  tables_data     JSONB         NOT NULL DEFAULT '[]'::jsonb,
  next_menu_id    INT           NOT NULL DEFAULT 1,
  next_session_id INT           NOT NULL DEFAULT 1,
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sg_sessions (
  id                TEXT         PRIMARY KEY,
  restaurant_id     TEXT         NOT NULL REFERENCES sg_restaurants(id) ON DELETE CASCADE,
  table_number      INT          NOT NULL,
  table_id          TEXT,
  join_code         TEXT         NOT NULL,
  status            TEXT         NOT NULL DEFAULT 'occupied',
  split_mode        TEXT         NOT NULL DEFAULT 'by_item',
  tax               NUMERIC(5,2) NOT NULL DEFAULT 0,
  tip               NUMERIC(5,2) NOT NULL DEFAULT 0,
  participants      JSONB        NOT NULL DEFAULT '[]'::jsonb,
  orders            JSONB        NOT NULL DEFAULT '[]'::jsonb,
  payments          JSONB        NOT NULL DEFAULT '[]'::jsonb,
  transferred_debts JSONB        NOT NULL DEFAULT '[]'::jsonb,
  opened_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  closed_at         TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS sg_sessions_active_code
  ON sg_sessions(join_code) WHERE status IN ('occupied', 'paying');

CREATE TABLE IF NOT EXISTS sg_history (
  id              BIGSERIAL    PRIMARY KEY,
  restaurant_id   TEXT         NOT NULL REFERENCES sg_restaurants(id) ON DELETE CASCADE,
  session_data    JSONB        NOT NULL,
  closed_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Agregar columnas nuevas (si no existen)
ALTER TABLE sg_restaurants
  ADD COLUMN IF NOT EXISTS payment_accounts JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE sg_restaurants
  ADD COLUMN IF NOT EXISTS dlocal_url TEXT NOT NULL DEFAULT '';

ALTER TABLE sg_restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE sg_sessions    DISABLE ROW LEVEL SECURITY;
ALTER TABLE sg_history     DISABLE ROW LEVEL SECURITY;

-- Realtime para el cliente
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE sg_sessions;
EXCEPTION WHEN OTHERS THEN
  -- Ya estaba agregada
END;
$$;

-- ─────────────────────────────────────────
-- PASO 9: Recrear función generate_join_code
-- ─────────────────────────────────────────

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
      RAISE EXCEPTION 'No se pudo generar código único después de 100 intentos';
    END IF;
  END LOOP;
  RETURN code;
END; $$;

-- ─────────────────────────────────────────
-- PASO 10: Recrear vistas
-- ─────────────────────────────────────────

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
  COALESCE(SUM(o.unit_price * o.qty), 0) * s.tip / 100 AS tip_amount
FROM sessions s
JOIN restaurants r ON r.id = s.restaurant_id
JOIN countries   c ON c.code = r.country_code
LEFT JOIN session_participants p ON p.session_id = s.id
LEFT JOIN orders o               ON o.session_id = s.id
GROUP BY s.id, r.id, c.code;

CREATE OR REPLACE VIEW v_participant_totals AS
SELECT
  sp.session_id,
  sp.id                                   AS person_id,
  sp.name                                 AS display_name,
  sp.color                                AS avatar_color,
  sp.is_proxy,
  COALESCE(SUM(
    CASE WHEN o.order_type = 'individual' AND o.person_id = sp.id
         THEN o.unit_price * o.qty ELSE 0 END
  ), 0)                                   AS own_items_total,
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
  COALESCE((
    SELECT SUM(td.amount) FROM transferred_debts td
    WHERE td.session_id = sp.session_id AND td.to_person_id = sp.id
  ), 0)                                   AS transferred_debt,
  COALESCE((
    SELECT SUM(py.amount) FROM payments py
    WHERE py.session_id = sp.session_id
      AND py.person_id  = sp.id
      AND py.status     = 'paid'
  ), 0)                                   AS paid_amount
FROM session_participants sp
LEFT JOIN orders o ON o.session_id = sp.session_id
GROUP BY sp.session_id, sp.id, sp.name, sp.color, sp.is_proxy;

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
JOIN sessions s                 ON s.id  = py.session_id
JOIN restaurants r              ON r.id  = s.restaurant_id
JOIN countries c                ON c.code = r.country_code
LEFT JOIN session_participants sp2 ON sp2.session_id = s.id
GROUP BY py.id, s.id, r.id, c.code;

-- ─────────────────────────────────────────
-- PASO 11: Datos de ejemplo en sg_restaurants
-- ─────────────────────────────────────────

INSERT INTO sg_restaurants (
  id, name, country, tax, tip, num_tables, address,
  next_menu_id, next_session_id, menu, tables_data
) VALUES (
  'demo@rinconcriollo.co',
  'El Rincón Criollo',
  'CO', 19, 10, 10,
  'Cra 7 #45-23, Bogotá',
  8, 1,
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
    {"id":"1","number":1,"status":"free"},{"id":"2","number":2,"status":"free"},
    {"id":"3","number":3,"status":"free"},{"id":"4","number":4,"status":"free"},
    {"id":"5","number":5,"status":"free"},{"id":"6","number":6,"status":"free"},
    {"id":"7","number":7,"status":"free"},{"id":"8","number":8,"status":"free"},
    {"id":"9","number":9,"status":"free"},{"id":"10","number":10,"status":"free"}
  ]'::jsonb
) ON CONFLICT (id) DO NOTHING;

COMMIT;
