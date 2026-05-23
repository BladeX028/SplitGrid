-- ================================================================
--  SplitGrid · Supabase Migration
--  Ejecutar en: Dashboard → SQL Editor
--  https://supabase.com/dashboard/project/jqwgmxavuvaklbszmfkp/editor
-- ================================================================

-- 1. Restaurantes (una fila por dueño de restaurante)
CREATE TABLE IF NOT EXISTS sg_restaurants (
  id              TEXT          PRIMARY KEY,          -- email del dueño
  name            TEXT          NOT NULL DEFAULT 'Mi Restaurante',
  country         TEXT          NOT NULL DEFAULT 'CO',
  tax             NUMERIC(5,2)  NOT NULL DEFAULT 19,
  tip             NUMERIC(5,2)  NOT NULL DEFAULT 10,
  num_tables      INT           NOT NULL DEFAULT 10,
  address         TEXT          NOT NULL DEFAULT '',
  menu            JSONB         NOT NULL DEFAULT '[]'::jsonb,
  tables_data     JSONB         NOT NULL DEFAULT '[]'::jsonb,
  next_menu_id     INT           NOT NULL DEFAULT 1,
  next_session_id  INT           NOT NULL DEFAULT 1,
  payment_accounts JSONB         NOT NULL DEFAULT '{}'::jsonb,
  dlocal_url       TEXT          NOT NULL DEFAULT '',
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- 2. Sesiones activas de mesa
CREATE TABLE IF NOT EXISTS sg_sessions (
  id                TEXT         PRIMARY KEY,         -- mismo ID que usa el app
  restaurant_id     TEXT         NOT NULL REFERENCES sg_restaurants(id) ON DELETE CASCADE,
  table_number      INT          NOT NULL,
  table_id          TEXT,
  join_code         TEXT         NOT NULL,
  status            TEXT         NOT NULL DEFAULT 'occupied',
  split_mode        TEXT         NOT NULL DEFAULT 'by_item',
  tax               NUMERIC(5,2) NOT NULL DEFAULT 19,
  tip               NUMERIC(5,2) NOT NULL DEFAULT 10,
  participants      JSONB        NOT NULL DEFAULT '[]'::jsonb,
  orders            JSONB        NOT NULL DEFAULT '[]'::jsonb,
  payments          JSONB        NOT NULL DEFAULT '[]'::jsonb,
  transferred_debts JSONB        NOT NULL DEFAULT '[]'::jsonb,
  opened_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  closed_at         TIMESTAMPTZ
);

-- Índice: un código de unión activo por vez
CREATE UNIQUE INDEX IF NOT EXISTS sg_sessions_active_code
  ON sg_sessions(join_code)
  WHERE status IN ('occupied', 'paying');

-- 3. Historial de sesiones cerradas
CREATE TABLE IF NOT EXISTS sg_history (
  id             BIGSERIAL    PRIMARY KEY,
  restaurant_id  TEXT         NOT NULL REFERENCES sg_restaurants(id) ON DELETE CASCADE,
  session_data   JSONB        NOT NULL,
  closed_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── RLS desactivado para prototipo ──
-- TODO: activar con políticas adecuadas antes de producción
ALTER TABLE sg_restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE sg_sessions    DISABLE ROW LEVEL SECURITY;
ALTER TABLE sg_history     DISABLE ROW LEVEL SECURITY;

-- ── Habilitar Realtime en sesiones (seguro en re-ejecuciones) ──
-- Permite que el cliente reciba actualizaciones del restaurante en tiempo real
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'sg_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE sg_sessions;
  END IF;
END $$;
