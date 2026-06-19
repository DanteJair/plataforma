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
