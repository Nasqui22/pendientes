-- La web ya no tiene proyectos personales (solo proyectos de equipo). Se borran los datos de esos proyectos;
-- las tareas NO se tocan: tareas.proyecto_id es "on delete set null", así que solo pierden el vínculo.
-- La tabla y la columna quedan sin uso (no se eliminan).
delete from public.proyectos;
