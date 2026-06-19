-- =============================================================================
-- Stitch · Gestión de Documentos
-- Esquema PostgreSQL (versión corregida para contenedor)
-- Compatible con PostgreSQL 14+
--
-- Este archivo se monta en /docker-entrypoint-initdb.d y se ejecuta
-- automáticamente la primera vez que arranca el contenedor de Postgres.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- EXTENSIONES  (deben ir ANTES de cualquier índice que las use)
-- Corrige el bug del script original donde pg_trgm se creaba después del índice.
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE SCHEMA IF NOT EXISTS stitch;
SET search_path TO stitch, public;

-- -----------------------------------------------------------------------------
-- TIPOS ENUMERADOS
-- -----------------------------------------------------------------------------
CREATE TYPE estado_documento AS ENUM (
    'pendiente',
    'completado',
    'en_revision',
    'archivado'
);

CREATE TYPE tipo_archivo AS ENUM (
    'pdf', 'xlsx', 'docx', 'csv', 'pptx', 'otro'
);

CREATE TYPE prioridad_documento AS ENUM (
    'baja', 'normal', 'alta', 'critica'
);

-- -----------------------------------------------------------------------------
-- TABLA: usuarios
-- -----------------------------------------------------------------------------
CREATE TABLE usuarios (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(120)  NOT NULL,
    correo          VARCHAR(255)  UNIQUE,
    iniciales       VARCHAR(8)    NOT NULL,
    es_sistema      BOOLEAN       NOT NULL DEFAULT FALSE,
    activo          BOOLEAN       NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ   NOT NULL DEFAULT now()
);

COMMENT ON TABLE  usuarios IS 'Autores y cuentas (incluye cuentas de sistema/automatización).';

-- -----------------------------------------------------------------------------
-- TABLA: documentos
-- -----------------------------------------------------------------------------
CREATE TABLE documentos (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    folio           VARCHAR(20)   NOT NULL UNIQUE,
    nombre          VARCHAR(255)  NOT NULL,
    tipo            tipo_archivo  NOT NULL,
    icono           VARCHAR(40),
    estado          estado_documento     NOT NULL DEFAULT 'pendiente',
    prioridad       prioridad_documento  NOT NULL DEFAULT 'normal',
    autor_id        BIGINT        NOT NULL
                        REFERENCES usuarios(id)
                        ON UPDATE CASCADE
                        ON DELETE RESTRICT,
    tamano_bytes    BIGINT        CHECK (tamano_bytes IS NULL OR tamano_bytes >= 0),
    -- Clave del objeto en MinIO (bucket "documentos"). NULL hasta que se sube.
    ruta_archivo    TEXT,
    fecha_creacion  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    eliminado_en    TIMESTAMPTZ,
    CONSTRAINT chk_folio_formato CHECK (folio ~ '^ST-[0-9]{3,}$')
);

COMMENT ON COLUMN documentos.ruta_archivo IS 'Object key en MinIO. Ej: documentos/ST-8829/archivo.pdf';
COMMENT ON COLUMN documentos.eliminado_en IS 'Borrado lógico (soft delete).';

-- -----------------------------------------------------------------------------
-- TABLA: etiquetas y relación N:M
-- -----------------------------------------------------------------------------
CREATE TABLE etiquetas (
    id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre  VARCHAR(60) NOT NULL UNIQUE,
    color   VARCHAR(9)
);

CREATE TABLE documento_etiquetas (
    documento_id BIGINT NOT NULL REFERENCES documentos(id) ON DELETE CASCADE,
    etiqueta_id  BIGINT NOT NULL REFERENCES etiquetas(id)  ON DELETE CASCADE,
    PRIMARY KEY (documento_id, etiqueta_id)
);

-- -----------------------------------------------------------------------------
-- TABLA: historial
-- -----------------------------------------------------------------------------
CREATE TABLE historial_documentos (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    documento_id  BIGINT NOT NULL REFERENCES documentos(id) ON DELETE CASCADE,
    usuario_id    BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
    accion        VARCHAR(40) NOT NULL,
    detalle       TEXT,
    ocurrido_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- ÍNDICES
-- -----------------------------------------------------------------------------
CREATE INDEX idx_documentos_estado     ON documentos(estado)        WHERE eliminado_en IS NULL;
CREATE INDEX idx_documentos_prioridad  ON documentos(prioridad)     WHERE eliminado_en IS NULL;
CREATE INDEX idx_documentos_autor      ON documentos(autor_id);
CREATE INDEX idx_documentos_fecha      ON documentos(fecha_creacion DESC);

-- Búsqueda trigram sobre nombre, folio (documentos) y nombre (usuarios).
-- Cubre los tres campos del buscador "nombre, autor o folio".
CREATE INDEX idx_documentos_nombre_trgm ON documentos USING gin (nombre gin_trgm_ops);
CREATE INDEX idx_documentos_folio_trgm  ON documentos USING gin (folio  gin_trgm_ops);
CREATE INDEX idx_usuarios_nombre_trgm   ON usuarios   USING gin (nombre gin_trgm_ops);

-- -----------------------------------------------------------------------------
-- TRIGGER: mantener actualizado_en
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_set_actualizado_en()
RETURNS TRIGGER AS $$
BEGIN
    NEW.actualizado_en = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_documentos_upd
    BEFORE UPDATE ON documentos
    FOR EACH ROW EXECUTE FUNCTION fn_set_actualizado_en();

CREATE TRIGGER trg_usuarios_upd
    BEFORE UPDATE ON usuarios
    FOR EACH ROW EXECUTE FUNCTION fn_set_actualizado_en();

-- -----------------------------------------------------------------------------
-- VISTAS (chips de filtro de la interfaz)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_documentos AS
SELECT
    d.id, d.folio, d.nombre, d.tipo, d.icono, d.estado, d.prioridad,
    d.fecha_creacion, d.tamano_bytes, d.ruta_archivo,
    u.id AS autor_id, u.nombre AS autor_nombre,
    u.iniciales AS autor_iniciales, u.es_sistema
FROM documentos d
JOIN usuarios u ON u.id = d.autor_id
WHERE d.eliminado_en IS NULL;

CREATE OR REPLACE VIEW v_documentos_pendientes  AS SELECT * FROM v_documentos WHERE estado = 'pendiente';
CREATE OR REPLACE VIEW v_documentos_completados AS SELECT * FROM v_documentos WHERE estado = 'completado';
CREATE OR REPLACE VIEW v_documentos_recientes   AS SELECT * FROM v_documentos WHERE fecha_creacion >= now() - INTERVAL '7 days';
CREATE OR REPLACE VIEW v_documentos_prioritarios AS SELECT * FROM v_documentos WHERE prioridad IN ('alta', 'critica');

-- -----------------------------------------------------------------------------
-- DATOS DE EJEMPLO
-- Las fechas usan now() - INTERVAL para que "Recientes" funcione en la demo.
-- -----------------------------------------------------------------------------
INSERT INTO usuarios (nombre, correo, iniciales, es_sistema) VALUES
    ('Juan Delgado',   'juan.delgado@stitch.io', 'JD',  FALSE),
    ('Maria Aranda',   'maria.aranda@stitch.io', 'MA',  FALSE),
    ('Automatización',  NULL,                    'SYS', TRUE),
    ('Roberto Luna',   'roberto.luna@stitch.io', 'RL',  FALSE);

INSERT INTO documentos (folio, nombre, tipo, icono, estado, prioridad, autor_id, fecha_creacion) VALUES
    ('ST-8829', 'Reporte_Anual_Q4_2023.pdf', 'pdf', 'description',
        'completado', 'normal',
        (SELECT id FROM usuarios WHERE nombre = 'Juan Delgado'),
        now() - INTERVAL '3 days'),

    ('ST-8901', 'Auditoria_Infraestructura_V1.xlsx', 'xlsx', 'analytics',
        'pendiente', 'alta',
        (SELECT id FROM usuarios WHERE nombre = 'Maria Aranda'),
        now() - INTERVAL '4 hours'),

    ('ST-7712', 'Contrato_Servicios_AWS_signed.pdf', 'pdf', 'contract',
        'completado', 'normal',
        (SELECT id FROM usuarios WHERE nombre = 'Automatización'),
        now() - INTERVAL '11 days'),

    ('ST-9011', 'Plan_Estrategico_2024.docx', 'docx', 'folder_shared',
        'pendiente', 'critica',
        (SELECT id FROM usuarios WHERE nombre = 'Roberto Luna'),
        now() - INTERVAL '1 day');
