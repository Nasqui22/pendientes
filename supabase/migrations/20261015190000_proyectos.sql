-- Proyectos personales: agrupador propio de cada usuario para filtrar el tablero.
-- El nombre vive en su propia tabla (RLS por dueño); la tarea solo guarda el id,
-- así un responsable que ve una tarea compartida no lee el nombre del proyecto.

create table if not exists public.proyectos (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nombre     text not null check (char_length(btrim(nombre)) between 1 and 40),
  created_at bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create unique index if not exists proyectos_nombre_uq on public.proyectos (user_id, lower(btrim(nombre)));

alter table public.proyectos enable row level security;
create policy "dueño lee proyectos"    on public.proyectos for select using (auth.uid() = user_id);
create policy "dueño crea proyectos"   on public.proyectos for insert with check (auth.uid() = user_id);
create policy "dueño edita proyectos"  on public.proyectos for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "dueño borra proyectos"  on public.proyectos for delete using (auth.uid() = user_id);

alter table public.tareas
  add column if not exists proyecto_id uuid references public.proyectos(id) on delete set null;
