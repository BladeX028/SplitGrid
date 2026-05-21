-- ============================================================
--  SplitGrid · PostgreSQL Schema completo
--  Version: 1.0
-- ============================================================

-- Extensiones
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─────────────────────────────────────────
-- ENUM TYPES
-- ─────────────────────────────────────────

CREATE TYPE user_role       AS ENUM ('owner', 'staff', 'customer');
CREATE TYPE table_status    AS ENUM ('free', 'occupied', 'paying', 'closed');
CREATE TYPE order_type      AS ENUM ('individual', 'shared');
CREATE TYPE order_status    AS ENUM ('pending', 'confirmed', 'delivered', 'cancelled');
CREATE TYPE payment_status  AS ENUM ('pending', 'processing', 'paid', 'failed', 'refunded');
CREATE TYPE payment_method  AS ENUM ('nequi', 'daviplata', 'pse', 'card', 'efecty', 'pix', 'carte_bleue', 'apple_pay', 'google_pay', 'sbp', 'cash');
CREATE TYPE split_mode      AS ENUM ('equal', 'by_item', 'custom');
CREATE TYPE currency_code   AS ENUM ('COP', 'BRL', 'EUR', 'RUB', 'USD', 'MXN', 'ARS', 'PEN', 'CLP');

-- ─────────────────────────────────────────
-- COUNTRIES & CURRENCIES
-- ─────────────────────────────────────────

CREATE TABLE countries (
  code          CHAR(2)        PRIMARY KEY,        -- ISO 3166-1 alpha-2
  name          VARCHAR(100)   NOT NULL,
  flag_emoji    CHAR(8)        NOT NULL,
  currency      currency_code  NOT NULL,
  currency_sym  VARCHAR(5)     NOT NULL,
  tax_pct       NUMERIC(5,2)   NOT NULL DEFAULT 0,
  tip_pct_def   NUMERIC(5,2)   NOT NULL DEFAULT 0,
  payment_methods payment_method[] NOT NULL DEFAULT '{cash}'
);

INSERT INTO countries VALUES
  ('CO','Colombia',       '🇨🇴','COP','$',    19, 10, '{nequi,daviplata,pse,card,efecty,cash}'),
  ('BR','Brasil',         '🇧🇷','BRL','R$',   0,  10, '{pix,card,cash}'),
  ('FR','Francia',        '🇫🇷','EUR','€',    20, 0,  '{carte_bleue,apple_pay,google_pay,card,cash}'),
  ('RU','Rusia',          '🇷🇺','RUB','₽',    20, 0,  '{sbp,card,cash}'),
  ('MX','México',         '🇲🇽','MXN','$',    16, 10, '{card,cash}'),
  ('US','Estados Unidos', '🇺🇸','USD','$',    0,  18, '{card,apple_pay,google_pay,cash}'),
  ('AR','Argentina',      '🇦🇷','ARS','$',    21, 10, '{card,cash}'),
  ('PE','Perú',           '🇵🇪','PEN','S/',   18, 10, '{card,cash}'),
  ('CL','Chile',          '🇨🇱','CLP','$',    19, 10, '{card,cash}');

-- ─────────────────────────────────────────
-- USERS
-- ─────────────────────────────────────────

CREATE TABLE users (
  id            UUID           PRIMARY KEY DEFAULT uuid_generate_v4(),
  email         VARCHAR(255)   UNIQUE,                        -- NULL si es guest
  display_name  VARCHAR(100)   NOT NULL,
  avatar_initials CHAR(3),
  avatar_color  VARCHAR(50),                                  -- gradient css value
  role          user_role      NOT NULL DEFAULT 'customer',
  country_code  CHAR(2)        REFERENCES countries(code),
  is_guest      BOOLEAN        NOT NULL DEFAULT false,
  guest_token   UUID           UNIQUE DEFAULT uuid_generate_v4(),
  password_hash TEXT,
  phone         VARCHAR(30),
  preferred_payment payment_method,
  created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  last_seen_at  TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- Index para búsqueda por email y guest_token
CREATE INDEX idx_users_email       ON users(email) WHERE email IS NOT NULL;
CREATE INDEX idx_users_guest_token ON users(guest_token);

-- ─────────────────────────────────────────
-- RESTAURANTS
-- ─────────────────────────────────────────

CREATE TABLE restaurants (
  id              UUID           PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id        UUID           NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name            VARCHAR(150)   NOT NULL,
  slug            VARCHAR(100)   UNIQUE NOT NULL,             -- URL: splitgrid.app/r/el-rincon
  country_code    CHAR(2)        NOT NULL REFERENCES countries(code),
  address         TEXT,
  phone           VARCHAR(30),
  logo_url        TEXT,
  tax_pct         NUMERIC(5,2)   NOT NULL DEFAULT 19,
  tip_pct_default NUMERIC(5,2)   NOT NULL DEFAULT 10,
  tip_optional    BOOLEAN        NOT NULL DEFAULT true,
  accepted_methods payment_method[] NOT NULL DEFAULT '{card,cash}',
  num_tables      SMALLINT       NOT NULL DEFAULT 10,
  is_active       BOOLEAN        NOT NULL DEFAULT true,
  plan            VARCHAR(20)    NOT NULL DEFAULT 'free',     -- free | pro | enterprise
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_restaurants_owner  ON restaurants(owner_id);
CREATE INDEX idx_restaurants_slug   ON restaurants(slug);
CREATE INDEX idx_restaurants_country ON restaurants(country_code);

-- Trigger: updated_at automático
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$;

CREATE TRIGGER trg_restaurants_updated_at
  BEFORE UPDATE ON restaurants
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Staff del restaurante
CREATE TABLE restaurant_staff (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id   UUID        NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role            VARCHAR(30) NOT NULL DEFAULT 'waiter',      -- waiter | manager | cashier
  active          BOOLEAN     NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(restaurant_id, user_id)
);

-- ─────────────────────────────────────────
-- MENU
-- ─────────────────────────────────────────

CREATE TABLE menu_categories (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id UUID        NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name          VARCHAR(80) NOT NULL,
  emoji         CHAR(8),
  sort_order    SMALLINT    NOT NULL DEFAULT 0,
  is_active     BOOLEAN     NOT NULL DEFAULT true
);

CREATE INDEX idx_menu_cat_restaurant ON menu_categories(restaurant_id);

CREATE TABLE menu_items (
  id            UUID           PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id UUID           NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  category_id   UUID           REFERENCES menu_categories(id) ON DELETE SET NULL,
  name          VARCHAR(150)   NOT NULL,
  description   TEXT,
  emoji         CHAR(8),
  price         NUMERIC(12,2)  NOT NULL,
  is_available  BOOLEAN        NOT NULL DEFAULT true,
  is_shareable  BOOLEAN        NOT NULL DEFAULT true,
  sort_order    SMALLINT       NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_menu_items_restaurant ON menu_items(restaurant_id);
CREATE INDEX idx_menu_items_category   ON menu_items(category_id);
CREATE INDEX idx_menu_items_available  ON menu_items(restaurant_id, is_available);

CREATE TRIGGER trg_menu_items_updated_at
  BEFORE UPDATE ON menu_items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ─────────────────────────────────────────
-- TABLES (mesas)
-- ─────────────────────────────────────────

CREATE TABLE tables (
  id            UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id UUID         NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  number        SMALLINT     NOT NULL,
  label         VARCHAR(50),                                  -- "Terraza 3", "Barra 1", etc.
  capacity      SMALLINT     NOT NULL DEFAULT 4,
  qr_code_url   TEXT,
  status        table_status NOT NULL DEFAULT 'free',
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE(restaurant_id, number)
);

CREATE INDEX idx_tables_restaurant ON tables(restaurant_id);
CREATE INDEX idx_tables_status     ON tables(restaurant_id, status);

-- ─────────────────────────────────────────
-- SESSIONS (instancias de mesa activa)
-- ─────────────────────────────────────────

CREATE TABLE sessions (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id UUID        NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  table_id      UUID        NOT NULL REFERENCES tables(id),
  join_code     CHAR(6)     NOT NULL UNIQUE,                 -- código de 6 chars para unirse
  split_mode    split_mode  NOT NULL DEFAULT 'by_item',
  status        table_status NOT NULL DEFAULT 'occupied',
  tax_pct       NUMERIC(5,2) NOT NULL,
  tip_pct       NUMERIC(5,2) NOT NULL,
  opened_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at     TIMESTAMPTZ,
  total_amount  NUMERIC(14,2) GENERATED ALWAYS AS STORED -- calculado por view/trigger
    DEFAULT NULL                                           -- se llena al cerrar
);

-- Simplificamos: total_amount es columna normal, se actualiza al cerrar
ALTER TABLE sessions DROP COLUMN IF EXISTS total_amount;
ALTER TABLE sessions ADD COLUMN total_amount NUMERIC(14,2);

CREATE INDEX idx_sessions_restaurant ON sessions(restaurant_id);
CREATE INDEX idx_sessions_table      ON sessions(table_id);
CREATE INDEX idx_sessions_join_code  ON sessions(join_code);
CREATE INDEX idx_sessions_status     ON sessions(status);

-- Participantes de la sesión
CREATE TABLE session_participants (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id    UUID        NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  display_name  VARCHAR(100) NOT NULL,
  avatar_color  VARCHAR(50),
  joined_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  left_at       TIMESTAMPTZ,
  is_active     BOOLEAN     NOT NULL DEFAULT true,
  UNIQUE(session_id, user_id)
);

CREATE INDEX idx_participants_session ON session_participants(session_id);
CREATE INDEX idx_participants_user    ON session_participants(user_id);

-- ─────────────────────────────────────────
-- ORDERS
-- ─────────────────────────────────────────

CREATE TABLE orders (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id      UUID          NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  menu_item_id    UUID          NOT NULL REFERENCES menu_items(id),
  quantity        SMALLINT      NOT NULL DEFAULT 1,
  unit_price      NUMERIC(12,2) NOT NULL,                   -- snapshot del precio al pedir
  total_price     NUMERIC(14,2) NOT NULL,                   -- unit_price * quantity
  order_type      order_type    NOT NULL DEFAULT 'individual',
  status          order_status  NOT NULL DEFAULT 'pending',
  notes           TEXT,
  created_by      UUID          NOT NULL REFERENCES users(id),
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_orders_session    ON orders(session_id);
CREATE INDEX idx_orders_created_by ON orders(created_by);
CREATE INDEX idx_orders_status     ON orders(status);

CREATE TRIGGER trg_orders_updated_at
  BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Quién comparte cada order (para type='shared')
CREATE TABLE order_participants (
  order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  share_pct   NUMERIC(6,3),                                 -- NULL = partes iguales
  PRIMARY KEY (order_id, user_id)
);

CREATE INDEX idx_order_participants_order ON order_participants(order_id);
CREATE INDEX idx_order_participants_user  ON order_participants(user_id);

-- ─────────────────────────────────────────
-- PAYMENTS
-- ─────────────────────────────────────────

CREATE TABLE payments (
  id              UUID           PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id      UUID           NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  user_id         UUID           NOT NULL REFERENCES users(id),
  amount          NUMERIC(14,2)  NOT NULL,
  subtotal        NUMERIC(14,2)  NOT NULL,
  tax_amount      NUMERIC(14,2)  NOT NULL DEFAULT 0,
  tip_amount      NUMERIC(14,2)  NOT NULL DEFAULT 0,
  method          payment_method NOT NULL,
  status          payment_status NOT NULL DEFAULT 'pending',
  reference_code  VARCHAR(50)    UNIQUE DEFAULT 'SGR-' || to_char(NOW(),'YYYY') || '-' || lpad(floor(random()*999999)::text,6,'0'),
  gateway_ref     TEXT,                                     -- referencia del proveedor de pagos
  rating          SMALLINT       CHECK (rating BETWEEN 1 AND 5),
  rating_comment  TEXT,
  paid_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payments_session ON payments(session_id);
CREATE INDEX idx_payments_user    ON payments(user_id);
CREATE INDEX idx_payments_status  ON payments(status);
CREATE INDEX idx_payments_ref     ON payments(reference_code);

CREATE TRIGGER trg_payments_updated_at
  BEFORE UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ─────────────────────────────────────────
-- VIEWS ÚTILES
-- ─────────────────────────────────────────

-- Resumen de sesión activa
CREATE OR REPLACE VIEW v_session_summary AS
SELECT
  s.id                              AS session_id,
  s.join_code,
  s.status,
  s.split_mode,
  s.tax_pct,
  s.tip_pct,
  s.opened_at,
  r.id                              AS restaurant_id,
  r.name                            AS restaurant_name,
  r.slug                            AS restaurant_slug,
  c.code                            AS country_code,
  c.flag_emoji,
  c.currency,
  c.currency_sym,
  t.number                          AS table_number,
  t.label                           AS table_label,
  COUNT(DISTINCT sp.id)             AS participant_count,
  COUNT(DISTINCT o.id)              AS order_count,
  COALESCE(SUM(o.total_price),0)    AS subtotal,
  COALESCE(SUM(o.total_price),0) * s.tax_pct / 100  AS tax_amount,
  COALESCE(SUM(o.total_price),0) * s.tip_pct / 100  AS tip_amount,
  COALESCE(SUM(o.total_price),0) * (1 + s.tax_pct/100 + s.tip_pct/100) AS grand_total
FROM sessions s
JOIN restaurants r ON r.id = s.restaurant_id
JOIN countries   c ON c.code = r.country_code
JOIN tables      t ON t.id = s.table_id
LEFT JOIN session_participants sp ON sp.session_id = s.id AND sp.is_active = true
LEFT JOIN orders o ON o.session_id = s.id AND o.status != 'cancelled'
GROUP BY s.id, r.id, c.code, t.id;

-- Cuánto debe pagar cada participante (modo by_item)
CREATE OR REPLACE VIEW v_participant_totals AS
SELECT
  sp.session_id,
  sp.user_id,
  sp.display_name,
  sp.avatar_color,
  -- items individuales propios
  COALESCE(SUM(CASE WHEN o.order_type='individual' AND o.created_by=sp.user_id
    THEN o.total_price ELSE 0 END), 0) AS own_items_total,
  -- share de items compartidos
  COALESCE(SUM(CASE WHEN o.order_type='shared'
    THEN o.total_price * COALESCE(op.share_pct/100, 1.0/NULLIF(
      (SELECT COUNT(*) FROM order_participants op2 WHERE op2.order_id=o.id),0))
    ELSE 0 END), 0) AS shared_items_total,
  -- total antes de impuestos/propina
  COALESCE(SUM(CASE WHEN o.order_type='individual' AND o.created_by=sp.user_id
    THEN o.total_price ELSE 0 END), 0) +
  COALESCE(SUM(CASE WHEN o.order_type='shared'
    THEN o.total_price * COALESCE(op.share_pct/100, 1.0/NULLIF(
      (SELECT COUNT(*) FROM order_participants op2 WHERE op2.order_id=o.id),0))
    ELSE 0 END), 0) AS subtotal,
  -- pago existente
  COALESCE(MAX(p.amount) FILTER (WHERE p.status='paid'), 0) AS paid_amount,
  MAX(p.status)  AS payment_status
FROM session_participants sp
LEFT JOIN orders o ON o.session_id = sp.session_id AND o.status != 'cancelled'
LEFT JOIN order_participants op ON op.order_id = o.id AND op.user_id = sp.user_id
LEFT JOIN payments p ON p.session_id = sp.session_id AND p.user_id = sp.user_id
GROUP BY sp.session_id, sp.user_id, sp.display_name, sp.avatar_color;

-- Historial de pagos del usuario con contexto
CREATE OR REPLACE VIEW v_payment_history AS
SELECT
  p.id            AS payment_id,
  p.user_id,
  p.amount,
  p.method,
  p.status,
  p.reference_code,
  p.rating,
  p.paid_at,
  p.created_at,
  r.name          AS restaurant_name,
  r.slug          AS restaurant_slug,
  c.flag_emoji,
  c.currency_sym,
  t.number        AS table_number,
  COUNT(DISTINCT sp2.id) AS table_participants
FROM payments p
JOIN sessions s   ON s.id = p.session_id
JOIN restaurants r ON r.id = s.restaurant_id
JOIN countries   c ON c.code = r.country_code
JOIN tables      t ON t.id = s.table_id
LEFT JOIN session_participants sp2 ON sp2.session_id = s.id
GROUP BY p.id, r.id, c.code, t.id;

-- ─────────────────────────────────────────
-- FUNCIONES HELPER
-- ─────────────────────────────────────────

-- Generar código de unión único de 6 chars (alfanumérico)
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
      code := code || substr(chars, floor(random()*length(chars)+1)::int, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM sessions WHERE join_code=code AND status IN ('occupied','paying'));
    tries := tries + 1;
    IF tries > 100 THEN RAISE EXCEPTION 'No se pudo generar código único'; END IF;
  END LOOP;
  RETURN code;
END; $$;

-- Abrir nueva sesión de mesa
CREATE OR REPLACE FUNCTION open_session(
  p_restaurant_id UUID,
  p_table_id      UUID,
  p_split_mode    split_mode DEFAULT 'by_item'
) RETURNS sessions LANGUAGE plpgsql AS $$
DECLARE
  v_restaurant restaurants%ROWTYPE;
  v_session    sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_restaurant FROM restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Restaurante no encontrado'; END IF;

  -- Verificar que la mesa esté libre
  IF EXISTS (
    SELECT 1 FROM sessions
    WHERE table_id = p_table_id AND status IN ('occupied','paying')
  ) THEN RAISE EXCEPTION 'La mesa ya tiene una sesión activa'; END IF;

  INSERT INTO sessions (restaurant_id, table_id, join_code, split_mode, tax_pct, tip_pct)
  VALUES (p_restaurant_id, p_table_id, generate_join_code(), p_split_mode,
          v_restaurant.tax_pct, v_restaurant.tip_pct_default)
  RETURNING * INTO v_session;

  -- Marcar mesa como ocupada
  UPDATE tables SET status = 'occupied' WHERE id = p_table_id;

  RETURN v_session;
END; $$;

-- Unirse a sesión por código
CREATE OR REPLACE FUNCTION join_session(
  p_join_code  CHAR(6),
  p_user_id    UUID,
  p_name       VARCHAR(100)
) RETURNS session_participants LANGUAGE plpgsql AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_part    session_participants%ROWTYPE;
BEGIN
  SELECT * INTO v_session FROM sessions
  WHERE join_code = upper(p_join_code) AND status IN ('occupied','paying');
  IF NOT FOUND THEN RAISE EXCEPTION 'Código inválido o sesión cerrada'; END IF;

  INSERT INTO session_participants (session_id, user_id, display_name)
  VALUES (v_session.id, p_user_id, p_name)
  ON CONFLICT (session_id, user_id) DO UPDATE
    SET display_name=p_name, is_active=true, left_at=NULL
  RETURNING * INTO v_part;

  RETURN v_part;
END; $$;

-- Registrar pago
CREATE OR REPLACE FUNCTION register_payment(
  p_session_id UUID,
  p_user_id    UUID,
  p_amount     NUMERIC,
  p_method     payment_method
) RETURNS payments LANGUAGE plpgsql AS $$
DECLARE
  v_session  sessions%ROWTYPE;
  v_payment  payments%ROWTYPE;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sesión no encontrada'; END IF;

  -- Calcular subtotal/tax/tip
  INSERT INTO payments (session_id, user_id, amount, subtotal, tax_amount, tip_amount, method, status, paid_at)
  VALUES (
    p_session_id, p_user_id, p_amount,
    p_amount / (1 + v_session.tax_pct/100 + v_session.tip_pct/100),
    p_amount * (v_session.tax_pct/100) / (1 + v_session.tax_pct/100 + v_session.tip_pct/100),
    p_amount * (v_session.tip_pct/100) / (1 + v_session.tax_pct/100 + v_session.tip_pct/100),
    p_method, 'paid', NOW()
  )
  RETURNING * INTO v_payment;

  -- Si todos pagaron → cambiar estado de mesa
  UPDATE sessions SET status = 'paying' WHERE id = p_session_id;

  RETURN v_payment;
END; $$;

-- ─────────────────────────────────────────
-- DATOS DE EJEMPLO
-- ─────────────────────────────────────────

-- Usuario dueño del restaurante
INSERT INTO users (id, email, display_name, avatar_initials, role, country_code, is_guest, password_hash)
VALUES (
  'a0000000-0000-0000-0000-000000000001',
  'admin@rinconcriollo.co',
  'Carlos Mendoza',
  'CM',
  'owner',
  'CO',
  false,
  crypt('Demo1234!', gen_salt('bf'))
);

-- Restaurante de ejemplo
INSERT INTO restaurants (id, owner_id, name, slug, country_code, address, tax_pct, tip_pct_default, num_tables, accepted_methods)
VALUES (
  'b0000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001',
  'El Rincón Criollo',
  'el-rincon-criollo',
  'CO',
  'Cra 7 #45-23, Bogotá',
  19, 10, 12,
  '{nequi,daviplata,pse,card,efecty,cash}'
);

-- Mesas
INSERT INTO tables (restaurant_id, number, capacity) VALUES
  ('b0000000-0000-0000-0000-000000000001', 1,  4),
  ('b0000000-0000-0000-0000-000000000001', 2,  2),
  ('b0000000-0000-0000-0000-000000000001', 3,  6),
  ('b0000000-0000-0000-0000-000000000001', 4,  4),
  ('b0000000-0000-0000-0000-000000000001', 5,  4),
  ('b0000000-0000-0000-0000-000000000001', 6,  8),
  ('b0000000-0000-0000-0000-000000000001', 7,  4),
  ('b0000000-0000-0000-0000-000000000001', 8,  2),
  ('b0000000-0000-0000-0000-000000000001', 9,  6),
  ('b0000000-0000-0000-0000-000000000001', 10, 4),
  ('b0000000-0000-0000-0000-000000000001', 11, 8),
  ('b0000000-0000-0000-0000-000000000001', 12, 10);

-- Categorías del menú
INSERT INTO menu_categories (id, restaurant_id, name, emoji, sort_order) VALUES
  ('c0000001-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','Platos Fuertes','🍛',1),
  ('c0000001-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000001','Entradas','🥗',2),
  ('c0000001-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000001','Bebidas','🥤',3),
  ('c0000001-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000001','Postres','🍰',4);

-- Items del menú
INSERT INTO menu_items (restaurant_id, category_id, name, emoji, price, is_shareable) VALUES
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000001','Bandeja Paisa',   '🍛',42000,false),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000001','Ajiaco Bogotano', '🍜',35000,false),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000001','Picada Mixta',    '🥩',74000,true),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000001','Cazuela de Mariscos','🦐',58000,true),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000002','Ensalada Caesar', '🥗',22000,false),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000002','Patacones',       '🍟',12000,true),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000003','Aguapanela',      '🍵', 8000,false),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000003','Limonada de Coco','🥥',12000,false),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000003','Cerveza Artesanal','🍺',14000,true),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000003','Vino Copa',       '🍷',22000,false),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000004','Postre Tres Leches','🍰',18000,false),
  ('b0000000-0000-0000-0000-000000000001','c0000001-0000-0000-0000-000000000004','Churros con Arequipe','🍩',15000,true);
