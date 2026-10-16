-- Dependencias entre tareas: "tarea_id depende de bloqueada_por" (esta última debe terminar antes).
-- Pueden ser de proyectos distintos. Una relación solo existe para quien ve las dos tareas.
create table if not exists public.tarea_dependencias (
  id            uuid primary key default gen_random_uuid(),
  tarea_id      uuid not null references public.tareas(id) on delete cascade,   -- la que espera
  bloqueada_por uuid not null references public.tareas(id) on delete cascade,   -- la que tiene que terminar antes
  creada_por    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at    bigint not null default (extract(epoch from now()) * 1000)::bigint,
  unique (tarea_id, bloqueada_por),
  check (tarea_id <> bloqueada_por)
);
create index if not exists tarea_dependencias_bloq_idx on public.tarea_dependencias (bloqueada_por);
revoke all on public.tarea_dependencias from anon;
revoke truncate, references, trigger, update on public.tarea_dependencias from authenticated;

-- Dueño de la tarea o responsable que la ve.
create or replace function public.puede_gestionar_tarea(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.tareas t
    where t.id = p_id
      and (t.user_id = auth.uid() or public.ve_tarea_ajena(t.user_id, t.asignada_por, t.visible))
  );
$$;
revoke all on function public.puede_gestionar_tarea(uuid) from public, anon;
grant execute on function public.puede_gestionar_tarea(uuid) to authenticated;

alter table public.tarea_dependencias enable row level security;
create policy "ve dependencias de tareas que ve" on public.tarea_dependencias for select
  using (public.puede_ver_tarea(tarea_id) and public.puede_ver_tarea(bloqueada_por));
create policy "crea dependencias entre tareas que ve" on public.tarea_dependencias for insert
  with check (creada_por = auth.uid()
    and public.puede_ver_tarea(tarea_id) and public.puede_ver_tarea(bloqueada_por)
    and (public.puede_gestionar_tarea(tarea_id) or public.puede_gestionar_tarea(bloqueada_por)));
create policy "quita dependencias propias o de sus tareas" on public.tarea_dependencias for delete
  using (creada_por = auth.uid() or public.puede_gestionar_tarea(tarea_id) or public.puede_gestionar_tarea(bloqueada_por));

-- Sin ciclos (A depende de B depende de A) y con límites de uso.
create or replace function public.dependencias_validar()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_now bigint := (extract(epoch from now()) * 1000)::bigint; n bigint;
begin
  if exists (
    with recursive cadena(id) as (
      select new.bloqueada_por
      union
      select d.bloqueada_por from public.tarea_dependencias d join cadena c on d.tarea_id = c.id
    )
    select 1 from cadena where id = new.tarea_id
  ) then
    raise exception 'Esa relación crearía un círculo: una de las tareas ya depende de la otra.' using errcode = 'P0001';
  end if;
  select count(*) into n from public.tarea_dependencias where tarea_id = new.tarea_id;
  if n >= 20 then raise exception 'Una tarea puede depender de hasta 20 tareas.' using errcode = 'P0001'; end if;
  select count(*) into n from public.tarea_dependencias where creada_por = new.creada_por and created_at > v_now - 3600000;
  if n >= 100 then raise exception 'Demasiadas relaciones en la última hora. Probá más tarde.' using errcode = 'P0001'; end if;
  return new;
end $$;
revoke execute on function public.dependencias_validar() from public, anon, authenticated;
drop trigger if exists dependencias_validar_t on public.tarea_dependencias;
create trigger dependencias_validar_t before insert on public.tarea_dependencias
  for each row execute function public.dependencias_validar();
