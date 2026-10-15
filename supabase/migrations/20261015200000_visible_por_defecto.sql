-- Las tareas pasan a ser visibles para los responsables por defecto.
-- La persona puede desmarcar la casilla en cada tarea para dejarla privada.
alter table public.tareas alter column visible set default true;
update public.tareas set visible = true where not visible;
