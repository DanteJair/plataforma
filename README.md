https://claude.ai/share/5604d759-21cb-479c-97e2-af917f715cc9

Necesitas tener **Docker Desktop** (Windows/Mac) o **Docker Engine + el plugin compose** (Linux) instalado. Si ya lo tienes, son tres pasos.

## Pasos

**1. Abre una terminal y entra a la carpeta del proyecto**

Primero descomprime el `stitch.zip` que te pasé, y luego:
```bash
cd stitch
```
Debes estar en la carpeta donde está el archivo `docker-compose.yml` (verifícalo con `ls`).

**2. (Opcional) Crea tu archivo de configuración**
```bash
cp .env.example .env
```
Si te lo saltas, funciona igual con las credenciales por defecto (`stitch`/`minioadmin`). Solo cámbialas si vas a producción.

**3. Levanta todo**
```bash
docker compose up --build
```

Eso construye la imagen de Python y arranca los cuatro servicios (Postgres, Redis, MinIO y la API) en orden. La primera vez tarda un poco porque descarga las imágenes base y ejecuta `init.sql`.

## Verifica que funciona

Cuando veas en los logs que la API arrancó, abre en el navegador:

- `http://localhost:8000/docs` — documentación interactiva de la API
- `http://localhost:8000/health` — debe mostrar los cuatro servicios en `"ok"`
- `http://localhost:9001` — consola de MinIO (usuario/clave: `minioadmin`)

O desde otra terminal:
```bash
curl http://localhost:8000/documentos?por_pagina=4
```
Deberías recibir los 4 documentos de ejemplo.

## Comandos útiles

```bash
docker compose up -d --build   # arranca en segundo plano (no ocupa la terminal)
docker compose logs -f api     # ver los logs solo de la API
docker compose ps              # ver qué contenedores están corriendo
docker compose down            # detener y borrar los contenedores
docker compose down -v         # detener Y borrar los datos (Postgres + MinIO)
```

Un detalle importante: `init.sql` solo se ejecuta la **primera vez** que se crea el volumen de Postgres. Si cambias el esquema después, tienes que correr `docker compose down -v` para que vuelva a cargarlo desde cero (ojo, eso borra los datos).

## Si algo falla

El error más común es **"Cannot connect to the Docker daemon"** → significa que Docker no está corriendo; abre Docker Desktop y espera a que arranque.

Si un puerto está ocupado (por ejemplo el 5432 porque ya tienes Postgres local), verás un error de *port already allocated*; ahí puedes cambiar el mapeo en el `docker-compose.yml` (ej. `"5433:5432"`).

¿En qué sistema operativo estás? Si me dices, te confirmo cómo instalar Docker si aún no lo tienes.

¡Vamos! Voy a conectar el frontend real de Stitch a tu API. Antes hay un detalle técnico que tengo que resolver: las descargas.

El endpoint `/url` que hice genera una URL prefirmada de MinIO que apunta a `minio:9000` — ese nombre solo existe *dentro* de la red de Docker, así que tu navegador no podría abrirla. Para que las descargas funcionen desde el navegador, añado un endpoint que transmite el archivo a través de la API (`localhost:8000`). Eso requiere reconstruir el contenedor `api`, pero es un solo comando.

Primero actualizo la capa de almacenamiento:Ahora añado el endpoint de descarga por streaming al router:Ahora construyo el frontend conectado a la API, conservando el diseño original de Stitch:Empaqueto todo de nuevo, con el frontend y la API actualizada:Listo. Te dejé dos cosas: el **frontend conectado** (`stitch-frontend.html`) y el **proyecto completo actualizado** (`stitch.zip`, ya con el nuevo endpoint de descarga). Para verlo funcionando son dos pasos.

## Paso 1 — Reconstruir la API (por el cambio de descarga)

En una terminal, dentro de tu carpeta `stitch`:

```
docker compose up -d --build api
```

Esto reconstruye solo el contenedor de la API con el endpoint nuevo y lo deja en segundo plano (la `-d` libera la terminal). Postgres, Redis y MinIO siguen corriendo sin tocarse. Tarda poco porque las imágenes ya están.

## Paso 2 — Abrir el frontend

Reemplaza el `index.html` dentro de la carpeta `stitch/frontend/` con el archivo que descargaste (o usa el del zip nuevo), y **haz doble clic** para abrirlo en el navegador. Como tu API tiene CORS abierto, funciona directamente desde el archivo.

## Qué vas a poder probar

Todo conectado a los datos reales de tu Postgres:

- **La tabla** carga los documentos desde la API (verás los 4 de ejemplo).
- **Indicador de conexión** arriba a la derecha: si dice "Servicios OK" en verde, los tres servicios responden.
- **Chips de filtro** (Todos / Pendientes / Completados / Recientes / Prioritarios) — cada uno consulta su vista SQL.
- **Buscador**: escribe "auditoria", "juan" o "8829" y filtra por nombre, autor o folio en vivo.
- **Botón "Nuevo Documento"**: sube un archivo real → va a MinIO, se le asigna folio `ST-####` automático y aparece en la tabla. Verifícalo también en la consola de MinIO (`localhost:9001`).
- **Descargar**: funciona en los documentos que tú subas. En los 4 de ejemplo te avisará que no tienen archivo asociado (se insertaron solo como metadatos en el SQL, sin binario) — eso es lo esperado.
- **Eliminar**: hace el *soft delete* (marca `eliminado_en`); la fila desaparece de la tabla pero sigue en la base.

Un detalle de la caché de Redis: si subes o eliminas, el frontend refresca y verás el cambio porque la API invalida la caché en cada escritura. Pero si modificas la base directamente con SQL, el listado puede tardar hasta 60 segundos en reflejarlo (es el TTL que pusimos).

Si la tabla se queda en "No se pudo conectar con la API", revisa que el contenedor `api` esté arriba con `docker compose ps` y que la constante `API` al inicio del `<script>` apunte a `http://localhost:8000`.

¿Quieres que añada algo más, como editar el estado de un documento desde la tabla (un dropdown que haga PATCH), o paginación del lado del buscador?
