# Stitch · Gestión de Documentos

Backend contenedorizado para la interfaz **Stitch**. Conecta tres servicios
mediante una API en Python:

| Servicio   | Rol                                   | Puerto |
|------------|---------------------------------------|--------|
| PostgreSQL | Metadatos de los documentos           | 5432   |
| MinIO      | Almacenamiento de los archivos físicos| 9000 / 9001 |
| Redis      | Caché de listados y búsquedas         | 6379   |
| API (FastAPI) | Une todo y expone los endpoints    | 8000   |

La idea: Postgres guarda **qué** documento es (folio, nombre, estado, autor…),
MinIO guarda **el archivo en sí**, y Redis acelera las lecturas repetidas.

## Arranque

```bash
cp .env.example .env      # opcional, ajusta credenciales
docker compose up --build
```

La primera vez, `db/init.sql` crea el esquema y carga los 4 documentos de
ejemplo del diseño original.

## Verificar

- API y documentación interactiva: http://localhost:8000/docs
- Estado de los servicios: http://localhost:8000/health
- Consola de MinIO: http://localhost:9001 (usuario/clave de `.env`)

## Endpoints principales

Cada uno corresponde a un elemento de la interfaz:

| Interfaz                         | Endpoint |
|----------------------------------|----------|
| Tabla principal + chips de filtro| `GET /documentos?filtro=todos&pagina=1` |
| Buscar por nombre/autor/folio    | `GET /documentos/buscar?q=reporte` |
| Botón "Nuevo Documento"          | `POST /documentos` (multipart) |
| Botón "Descargar"                | `GET /documentos/{folio}/url` |
| Botón "Eliminar"                 | `DELETE /documentos/{folio}` (soft delete) |
| Columna "Autor"                  | `GET /usuarios` |

Filtros válidos: `todos`, `pendientes`, `completados`, `recientes`, `prioritarios`.

### Ejemplos

```bash
# Listar (igual que la tabla: 4 por página)
curl "http://localhost:8000/documentos?filtro=todos&por_pagina=4"

# Buscar
curl "http://localhost:8000/documentos/buscar?q=auditoria"

# Subir un documento
curl -F "autor_id=1" -F "estado=pendiente" -F "prioridad=alta" \
     -F "archivo=@/ruta/a/archivo.pdf" \
     http://localhost:8000/documentos

# Obtener URL de descarga (válida 15 min)
curl "http://localhost:8000/documentos/ST-8829/url"

# Eliminar (soft delete)
curl -X DELETE "http://localhost:8000/documentos/ST-9011"
```

## Estructura

```
stitch/
├── docker-compose.yml      # orquesta los 4 contenedores
├── .env.example
├── db/
│   └── init.sql            # esquema corregido + datos de ejemplo
└── app/
    ├── Dockerfile
    ├── requirements.txt
    ├── config.py           # settings desde variables de entorno
    ├── database.py         # pool de conexiones a Postgres
    ├── cache.py            # capa Redis
    ├── storage.py          # capa MinIO
    ├── schemas.py          # contratos Pydantic
    ├── main.py             # app FastAPI + healthcheck
    └── routers/
        ├── documentos.py   # CRUD + búsqueda + subida
        └── usuarios.py
```

## Notas de diseño

- **Soft delete**: eliminar no borra la fila; marca `eliminado_en`. El archivo
  en MinIO se conserva (se puede cambiar en `routers/documentos.py`).
- **Folios automáticos**: al subir se genera el siguiente `ST-####`.
- **Caché**: cualquier escritura invalida todo el namespace `docs:*` en Redis.
- **URLs prefirmadas**: las descargas no exponen las credenciales de MinIO.
- **Search path**: cada conexión fija `search_path=stitch,public`, así no hay
  que calificar las tablas.
```
