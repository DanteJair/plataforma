-- =============================================================================
-- Stitch · Gestión de Documentos
-- Esquema de base de datos PostgreSQL
-- Compatible con PostgreSQL 14+
-- =============================================================================

-- Extensión para generar UUIDs (opcional, usada en folios/ids alternativos)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Esquema dedicado para mantener todo ordenado
CREATE SCHEMA IF NOT EXISTS stitch;
SET search_path TO stitch, public;

-- =============================================================================
-- TIPOS ENUMERADOS
-- =============================================================================

-- Estado del documento (chips/badges: Completado / Pendiente)
CREATE TYPE estado_documento AS ENUM (
    'pendiente',
    'completado',
    'en_revision',   -- estado extra útil para flujos de trabajo
    'archivado'
);

-- Tipo de archivo (deducido de la extensión: .pdf, .xlsx, .docx)
CREATE TYPE tipo_archivo AS ENUM (
    'pdf',
    'xlsx',
    'docx',
    'csv',
    'pptx',
    'otro'
);

-- Prioridad (para el filtro "Prioritarios")
CREATE TYPE prioridad_documento AS ENUM (
    'baja',
    'normal',
    'alta',
    'critica'
);

-- =============================================================================
-- TABLA: usuarios  (autores que aparecen en la columna "Autor")
-- =============================================================================
CREATE TABLE usuarios (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(120)  NOT NULL,
    correo          VARCHAR(255)  UNIQUE,
    -- Iniciales mostradas en el avatar (JD, MA, RL...). Se calculan por defecto
    -- pero pueden sobreescribirse (ej. "System").
    iniciales       VARCHAR(8)    NOT NULL,
    -- Marca si la cuenta es un proceso automático (autor "Automatización")
    es_sistema      BOOLEAN       NOT NULL DEFAULT FALSE,
    activo          BOOLEAN       NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ   NOT NULL DEFAULT now()
);

COMMENT ON TABLE  usuarios IS 'Autores y cuentas (incluye cuentas de sistema/automatización).';
COMMENT ON COLUMN usuarios.iniciales IS 'Iniciales para el avatar circular de la tabla.';

-- =============================================================================
-- TABLA: documentos  (cada fila de la tabla principal del HTML)
-- =============================================================================
CREATE TABLE documentos (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- Folio visible (#ST-8829). Lo guardamos sin el "#" y con índice único.
    folio           VARCHAR(20)   NOT NULL UNIQUE,

    nombre          VARCHAR(255)  NOT NULL,           -- Reporte_Anual_Q4_2023.pdf
    tipo            tipo_archivo  NOT NULL,
    icono           VARCHAR(40),                       -- ícono Material Symbols (description, analytics...)

    estado          estado_documento  NOT NULL DEFAULT 'pendiente',
    prioridad       prioridad_documento NOT NULL DEFAULT 'normal',

    autor_id        BIGINT        NOT NULL
                        REFERENCES usuarios(id)
                        ON UPDATE CASCADE
                        ON DELETE RESTRICT,

    -- Tamaño en bytes (opcional, útil para mostrar peso del archivo)
    tamano_bytes    BIGINT        CHECK (tamano_bytes IS NULL OR tamano_bytes >= 0),
    ruta_archivo    TEXT,                              -- ubicación física/objeto en storage

    fecha_creacion  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    eliminado_en    TIMESTAMPTZ,                       -- soft delete (botón "Eliminar")

    CONSTRAINT chk_folio_formato CHECK (folio ~ '^ST-[0-9]{3,}$')
);

COMMENT ON TABLE  documentos IS 'Documentos gestionados, una fila por documento de la tabla.';
COMMENT ON COLUMN documentos.eliminado_en IS 'Borrado lógico: si no es NULL el documento está eliminado.';

-- =============================================================================
-- TABLA: etiquetas  (opcional, para clasificar / filtrar)
-- =============================================================================
CREATE TABLE etiquetas (
    id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre  VARCHAR(60) NOT NULL UNIQUE,
    color   VARCHAR(9)  -- hex (#0052cc) opcional
);

CREATE TABLE documento_etiquetas (
    documento_id BIGINT NOT NULL REFERENCES documentos(id) ON DELETE CASCADE,
    etiqueta_id  BIGINT NOT NULL REFERENCES etiquetas(id)  ON DELETE CASCADE,
    PRIMARY KEY (documento_id, etiqueta_id)
);

-- =============================================================================
-- TABLA: historial  (bitácora de cambios de estado / acciones)
-- =============================================================================
CREATE TABLE historial_documentos (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    documento_id  BIGINT NOT NULL REFERENCES documentos(id) ON DELETE CASCADE,
    usuario_id    BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
    accion        VARCHAR(40) NOT NULL,            -- creado, descargado, cambio_estado, eliminado...
    detalle       TEXT,
    ocurrido_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- ÍNDICES (orientados a los filtros y la búsqueda del HTML)
-- =============================================================================
CREATE INDEX idx_documentos_estado     ON documentos(estado)          WHERE eliminado_en IS NULL;
CREATE INDEX idx_documentos_prioridad  ON documentos(prioridad)       WHERE eliminado_en IS NULL;
CREATE INDEX idx_documentos_autor      ON documentos(autor_id);
CREATE INDEX idx_documentos_fecha      ON documentos(fecha_creacion DESC);

-- Búsqueda por nombre / folio / autor (campo de búsqueda "Buscar por nombre, autor o folio...")
CREATE INDEX idx_documentos_nombre_trgm ON documentos USING gin (nombre gin_trgm_ops);
-- Requiere la extensión pg_trgm:
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =============================================================================
-- TRIGGER: mantener actualizado_en
-- =============================================================================
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

-- =============================================================================
-- VISTAS (corresponden a los filtros / chips de la interfaz)
-- =============================================================================

-- Vista base: documentos activos con datos del autor ya "unidos"
CREATE OR REPLACE VIEW v_documentos AS
SELECT
    d.id,
    d.folio,
    d.nombre,
    d.tipo,
    d.icono,
    d.estado,
    d.prioridad,
    d.fecha_creacion,
    d.tamano_bytes,
    u.id      AS autor_id,
    u.nombre  AS autor_nombre,
    u.iniciales AS autor_iniciales,
    u.es_sistema
FROM documentos d
JOIN usuarios u ON u.id = d.autor_id
WHERE d.eliminado_en IS NULL;

-- Chip "Pendientes"
CREATE OR REPLACE VIEW v_documentos_pendientes AS
SELECT * FROM v_documentos WHERE estado = 'pendiente';

-- Chip "Completados"
CREATE OR REPLACE VIEW v_documentos_completados AS
SELECT * FROM v_documentos WHERE estado = 'completado';

-- Chip "Recientes" (últimos 7 días)
CREATE OR REPLACE VIEW v_documentos_recientes AS
SELECT * FROM v_documentos
WHERE fecha_creacion >= now() - INTERVAL '7 days';

-- Chip "Prioritarios"
CREATE OR REPLACE VIEW v_documentos_prioritarios AS
SELECT * FROM v_documentos WHERE prioridad IN ('alta', 'critica');

-- =============================================================================
-- DATOS DE EJEMPLO (los mismos que muestra el HTML)
-- =============================================================================

INSERT INTO usuarios (nombre, correo, iniciales, es_sistema) VALUES
    ('Juan Delgado',    'juan.delgado@stitch.io',   'JD', FALSE),
    ('Maria Aranda',    'maria.aranda@stitch.io',   'MA', FALSE),
    ('Automatización',  NULL,                        'SYS', TRUE),
    ('Roberto Luna',    'roberto.luna@stitch.io',   'RL', FALSE);

INSERT INTO documentos (folio, nombre, tipo, icono, estado, prioridad, autor_id, fecha_creacion) VALUES
    ('ST-8829', 'Reporte_Anual_Q4_2023.pdf',         'pdf',  'description',
        'completado', 'normal',
        (SELECT id FROM usuarios WHERE nombre = 'Juan Delgado'),
        '2023-10-12 10:00:00-06'),

    ('ST-8901', 'Auditoria_Infraestructura_V1.xlsx',  'xlsx', 'analytics',
        'pendiente', 'alta',
        (SELECT id FROM usuarios WHERE nombre = 'Maria Aranda'),
        now() - INTERVAL '4 hours'),   -- "Hoy, 09:45 AM"

    ('ST-7712', 'Contrato_Servicios_AWS_signed.pdf',  'pdf',  'contract',
        'completado', 'normal',
        (SELECT id FROM usuarios WHERE nombre = 'Automatización'),
        '2023-10-08 12:00:00-06'),

    ('ST-9011', 'Plan_Estrategico_2024.docx',         'docx', 'folder_shared',
        'pendiente', 'critica',
        (SELECT id FROM usuarios WHERE nombre = 'Roberto Luna'),
        now() - INTERVAL '1 day');     -- "Ayer, 16:30 PM"

-- =============================================================================
-- CONSULTAS DE EJEMPLO
-- =============================================================================

-- 1) Tabla principal (lo que se ve en pantalla), ordenado por fecha
-- SELECT folio, nombre, estado, fecha_creacion, autor_nombre
-- FROM v_documentos
-- ORDER BY fecha_creacion DESC;

-- 2) Búsqueda libre por nombre, folio o autor
-- SELECT * FROM v_documentos
-- WHERE nombre ILIKE '%reporte%'
--    OR folio  ILIKE '%8829%'
--    OR autor_nombre ILIKE '%juan%';

-- 3) Paginación ("Mostrando 1 - 4 de 42 resultados")
-- SELECT * FROM v_documentos
-- ORDER BY fecha_creacion DESC
-- LIMIT 4 OFFSET 0;
