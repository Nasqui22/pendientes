-- Avances por tarea: registro de notas cortas con fecha, p. ej.
-- [{"t": 1760000000000, "x": "Hablé con el proveedor"}].
-- Solo agrega una columna con valor por defecto; no modifica ni borra datos
-- existentes. Las políticas RLS de `tareas` ya la cubren (se aplican por fila).

alter table public.tareas
  add column if not exists avances jsonb not null default '[]'::jsonb;

alter table public.tareas
  add constraint tareas_avances_es_arreglo check (jsonb_typeof(avances) = 'array');
