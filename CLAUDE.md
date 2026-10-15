# Pendientes

Tablero personal de tareas en tres estados (Pendiente, En proceso, Completado) con prioridad, fecha límite, notas y subtareas. Idioma de la interfaz: español rioplatense.

## Estructura
- `index.html`: toda la app (HTML, CSS y JS en un solo archivo, sin build). Carga `supabase-js` por CDN.
- `config.js`: URL del proyecto y clave pública `anon` de Supabase.
- `schema.sql`: copia de referencia del esquema inicial.
- `supabase/migrations/`: migraciones de la base. Fuente de verdad del esquema.
- `supabase/functions/admin-usuarios/`: Edge Function (alta, rol, activo y contraseña de usuarios). Verifica en el servidor que quien llama sea admin y usa `service_role` desde los secretos de Supabase, nunca desde el repo.
- `PRODUCT.md` y `DESIGN.md`: contexto de producto y sistema visual (Impeccable). `.impeccable/surfaces/` guarda el contrato de dirección; el resto de `.impeccable/` es descartable y está en `.gitignore`.

## Servicios
- Web publicada: https://nasqui22.github.io/pendientes/ (GitHub Pages, rama `main`, carpeta raíz).
- Repo: https://github.com/Nasqui22/pendientes (público).
- Supabase: proyecto `zeedhbokiyvowlgenkon`, ya enlazado con el CLI (`supabase`). Tabla `tareas` con RLS: cada fila pertenece a un usuario (`user_id = auth.uid()`). Login con email y contraseña, registros desactivados.
  - `perfiles` (uno por usuario de Auth, con `nombre`, `es_admin`, `activo`; se crea por trigger). Solo lectura desde la web: los cambios pasan por `admin-usuarios`.
  - `responsables` (`responsable_id`, `persona_id`): varios responsables por persona y cadenas de responsables, sin ciclos (trigger). Solo el admin asigna y quita.
  - El admin es un usuario aparte ("Administrador") que gestiona usuarios y relaciones; no ve las tareas de los demás.

## Flujo de trabajo
1. Probar en local: `python3 -m http.server 8000` y abrir http://localhost:8000. Usa la misma base que producción.
2. Si el cambio toca la base: crear una migración nueva en `supabase/migrations/` (nombre `AAAAMMDDHHMMSS_descripcion.sql`), mostrarla al usuario y aplicar con `supabase db push` solo después de su OK.
3. Publicar: commit y `git push` a `main`. Pages se actualiza solo en uno o dos minutos.

## Reglas
- El repo es público. Nunca poner en el repo ni en el chat la Secret key, `service_role`, la contraseña de la base ni tokens. La clave `anon` en `config.js` es pública por diseño.
- Pedir confirmación antes de cualquier cambio que borre o altere datos existentes (DROP, DELETE, UPDATE masivo, cambios de tipo de columna).
- La seguridad depende de las políticas RLS. Toda tabla nueva debe tener RLS activado y políticas por `user_id`.
- Mantener el diseño existente: variables CSS en `:root`, modo claro y oscuro, íconos SVG, mobile primero (mínimo 16px de margen lateral).
- El campo `done` y el esquema de columnas (`ord`, `created_at`, `done_at` y `status_at` como `bigint` en ms; `labels` como `jsonb` arreglo de textos, máx. 8 de 24 caracteres) están mapeados en `toRow` y `fromRow` de `index.html`. Si se agrega una columna, actualizar ambos. `status_at` se fija en `moveTo()` cada vez que cambia el estado; 0 significa "sin dato" y la web usa `created_at` de respaldo.
- Los usuarios se crean solo desde el panel de administración (Edge Function). Nunca crear usuarios con la `service_role` desde la web.
- La carpeta `supabase/.temp` no se versiona.
- Diseño: seguir `DESIGN.md` (un solo acento, Hanken Grotesk, tokens en `:root` con claro y oscuro sincronizados). Los cambios visuales grandes pasan por `/impeccable`.
- Equipo (migración `20261015180000`): un responsable ve las tareas de sus DIRECTOS solo si las asignó él o la persona las marcó `visible` y confirmó a ese responsable (`responsables.confirmado`). Asignar, validar, devolver y retirar pasan por funciones `security definer` (`asignar_tarea`, `validar_tarea`, `devolver_tarea`, `retirar_tarea`, `confirmar_responsables`); el trigger `tareas_proteger` impide escribir `asignada_por`, `validada_*`, `motivo_devolucion` y cambiar fecha/prioridad de una tarea asignada, y cierra el estado de una tarea validada. Validado = `validada_por` no nulo (no hay un cuarto estado). El tablero propio filtra `user_id` en la consulta porque RLS también deja pasar tareas del equipo.
- `avances` (jsonb `[{t, x}]`) y `proyectos` (tabla propia, `tareas.proyecto_id`) son personales. Las métricas se calculan en la web con las tareas ya cargadas; el equipo solo cuenta lo visible o asignado.

## Historia
La primera versión fue un artifact de Claude ("Pendientes") con la base interna de Claude. Ya no se usa; este repo es el proyecto real.
