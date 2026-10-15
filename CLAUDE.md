# Pendientes

Tablero personal de tareas en tres estados (Pendiente, En proceso, Completado) con prioridad, fecha límite, notas y subtareas. Idioma de la interfaz: español rioplatense.

## Estructura
- `index.html`: toda la app (HTML, CSS y JS en un solo archivo, sin build). Carga `supabase-js` por CDN.
- `config.js`: URL del proyecto y clave pública `anon` de Supabase.
- `schema.sql`: copia de referencia del esquema inicial.
- `supabase/migrations/`: migraciones de la base. Fuente de verdad del esquema.

## Servicios
- Web publicada: https://nasqui22.github.io/pendientes/ (GitHub Pages, rama `main`, carpeta raíz).
- Repo: https://github.com/Nasqui22/pendientes (público).
- Supabase: proyecto `zeedhbokiyvowlgenkon`, ya enlazado con el CLI (`supabase`). Tabla `tareas` con RLS: cada fila pertenece a un usuario (`user_id = auth.uid()`). Login con email y contraseña, registros desactivados.

## Flujo de trabajo
1. Probar en local: `python3 -m http.server 8000` y abrir http://localhost:8000. Usa la misma base que producción.
2. Si el cambio toca la base: crear una migración nueva en `supabase/migrations/` (nombre `AAAAMMDDHHMMSS_descripcion.sql`), mostrarla al usuario y aplicar con `supabase db push` solo después de su OK.
3. Publicar: commit y `git push` a `main`. Pages se actualiza solo en uno o dos minutos.

## Reglas
- El repo es público. Nunca poner en el repo ni en el chat la Secret key, `service_role`, la contraseña de la base ni tokens. La clave `anon` en `config.js` es pública por diseño.
- Pedir confirmación antes de cualquier cambio que borre o altere datos existentes (DROP, DELETE, UPDATE masivo, cambios de tipo de columna).
- La seguridad depende de las políticas RLS. Toda tabla nueva debe tener RLS activado y políticas por `user_id`.
- Mantener el diseño existente: variables CSS en `:root`, modo claro y oscuro, íconos SVG, mobile primero (mínimo 16px de margen lateral).
- El campo `done` y el esquema de columnas (`ord`, `created_at`, `done_at` como `bigint` en ms) están mapeados en `toRow` y `fromRow` de `index.html`. Si se agrega una columna, actualizar ambos.
- La carpeta `supabase/.temp` no se versiona.

## Historia
La primera versión fue un artifact de Claude ("Pendientes") con la base interna de Claude. Ya no se usa; este repo es el proyecto real.
