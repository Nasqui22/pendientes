-- Cualquier persona puede crear proyectos de equipo (antes solo quien tenía gente a cargo).
-- Quien lo crea es su líder: lo edita, carga hitos y asigna sus libros. Sin directos, el proyecto
-- se comparte igual con su equipo (compañeros y responsable) mientras esté abierto.
drop policy if exists "lider crea proyectos" on public.equipo_proyectos;
create policy "cualquiera crea proyectos propios" on public.equipo_proyectos for insert
  with check (lider_id = auth.uid());
