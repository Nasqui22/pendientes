-- Vincular tareas a un proyecto de equipo.
-- Solo se puede elegir un proyecto donde la persona es líder o miembro vigente.
-- Al borrarse el proyecto, las tareas quedan sin proyecto (no se borran).

alter table public.tareas
  add column if not exists equipo_proyecto_id uuid references public.equipo_proyectos(id) on delete set null;
create index if not exists tareas_equipo_proyecto_idx on public.tareas (equipo_proyecto_id);

create or replace function public.puede_usar_proyecto(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.es_lider_de_proyecto(p) or public.es_miembro_de_proyecto(p);
$$;
revoke all on function public.puede_usar_proyecto(uuid) from public, anon;
grant execute on function public.puede_usar_proyecto(uuid) to authenticated;

create or replace function public.tareas_proteger()
returns trigger language plpgsql as $$
begin
  -- Las funciones security definer corren como su dueño: pasan sin restricción.
  if current_user not in ('authenticated', 'anon') then return new; end if;

  if tg_op = 'INSERT' then
    new.asignada_por := null; new.validada_por := null; new.validada_at := 0;
    new.motivo_devolucion := ''; new.devuelta_at := 0;
  else
    new.user_id := old.user_id;
    new.asignada_por := old.asignada_por;
    new.validada_por := old.validada_por;
    new.validada_at := old.validada_at;
    new.motivo_devolucion := old.motivo_devolucion;
    new.devuelta_at := old.devuelta_at;

    if old.asignada_por is not null then
      new.due := old.due;
      new.prio := old.prio;
    end if;
    if old.validada_por is not null and new.status is distinct from old.status then
      raise exception 'La tarea ya fue validada.' using errcode = 'P0001';
    end if;
  end if;

  if new.equipo_proyecto_id is not null
     and (tg_op = 'INSERT' or new.equipo_proyecto_id is distinct from old.equipo_proyecto_id)
     and not public.puede_usar_proyecto(new.equipo_proyecto_id) then
    raise exception 'Solo podés vincular tareas a proyectos donde participás.' using errcode = 'P0001';
  end if;
  return new;
end $$;

-- Asignar con proyecto opcional (el líder solo puede usar sus proyectos y a sus miembros).
drop function if exists public.asignar_tarea(uuid, text, text, text, text);
create or replace function public.asignar_tarea(
  p_persona uuid, p_text text, p_prio text default '', p_due text default '', p_notes text default '',
  p_proyecto uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_now bigint := (extract(epoch from now()) * 1000)::bigint; v_ord bigint;
begin
  if auth.uid() is null then raise exception 'Sin sesión.'; end if;
  if not exists (select 1 from responsables where responsable_id = auth.uid() and persona_id = p_persona) then
    raise exception 'Solo podés asignar tareas a tus directos.';
  end if;
  p_text := btrim(coalesce(p_text, ''));
  if char_length(p_text) = 0 or char_length(p_text) > 300 then raise exception 'El título debe tener entre 1 y 300 caracteres.'; end if;
  if coalesce(p_prio, '') not in ('', 'alta', 'media', 'baja') then raise exception 'Prioridad inválida.'; end if;
  if coalesce(p_due, '') <> '' and p_due !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Fecha inválida.'; end if;
  if p_proyecto is not null and not exists (
      select 1 from equipo_proyectos pr join equipo_proyecto_miembros m on m.proyecto_id = pr.id
      where pr.id = p_proyecto and pr.lider_id = auth.uid() and m.persona_id = p_persona) then
    raise exception 'Ese proyecto no es tuyo o la persona no participa en él.';
  end if;
  select coalesce(max(ord), 0) + 1000 into v_ord from tareas where user_id = p_persona and status = 'pendiente';
  insert into tareas (user_id, text, status, prio, due, notes, ord, created_at, status_at, asignada_por, visible, equipo_proyecto_id)
  values (p_persona, p_text, 'pendiente', coalesce(p_prio, ''), coalesce(p_due, ''),
          left(coalesce(p_notes, ''), 5000), v_ord, v_now, v_now, auth.uid(), true, p_proyecto)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.asignar_tarea(uuid, text, text, text, text, uuid) from public, anon;
grant execute on function public.asignar_tarea(uuid, text, text, text, text, uuid) to authenticated;
