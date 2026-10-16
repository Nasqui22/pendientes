-- Proyectos de equipo abiertos: todo el equipo del líder (mismo_equipo: sus directos, su responsable y los
-- compañeros de este) puede ver el proyecto, sus hitos, miembros y libros, y vincular sus propias tareas.
-- Nadie más que el líder puede editarlo. El líder puede cerrarlo a solo sus miembros con "abierto = false".
alter table public.equipo_proyectos add column if not exists abierto boolean not null default true;

-- "Participa": es miembro vigente, o el proyecto está abierto y es de mi equipo.
-- Todas las políticas de lectura (proyecto, miembros, hitos, libros del proyecto) y puede_usar_proyecto
-- se apoyan en esta función; las de escritura siguen siendo solo del líder.
create or replace function public.es_miembro_de_proyecto(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.equipo_proyecto_miembros m
    join public.equipo_proyectos p on p.id = m.proyecto_id
    join public.responsables r on r.responsable_id = p.lider_id and r.persona_id = m.persona_id
    where m.proyecto_id = p_id and m.persona_id = auth.uid()
  ) or exists (
    select 1 from public.equipo_proyectos p
    where p.id = p_id and p.abierto and public.mismo_equipo(p.lider_id, auth.uid())
  );
$$;
