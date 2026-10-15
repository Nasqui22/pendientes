-- Etiquetas por tarea y fecha del último cambio de estado.
-- Solo agrega dos columnas con valor por defecto; no modifica ni borra datos
-- existentes. Las políticas RLS de `tareas` ya cubren las columnas nuevas
-- (se aplican por fila: cada tarea sigue siendo de su dueño).

alter table public.tareas
  add column if not exists labels    jsonb  not null default '[]'::jsonb,
  add column if not exists status_at bigint not null default 0;

-- labels: arreglo de textos, p. ej. ["Evento", "Urgente"].
-- status_at: ms desde epoch del último cambio de estado. 0 = sin dato (tareas
-- anteriores); la web usa entonces la fecha de creación como respaldo.
alter table public.tareas
  add constraint tareas_labels_es_arreglo check (jsonb_typeof(labels) = 'array');
