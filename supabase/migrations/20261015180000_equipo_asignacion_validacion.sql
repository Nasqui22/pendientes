-- Equipo: visibilidad para responsables, asignación de tareas y validación.
--
-- Reglas:
--  * Las tareas son privadas. Un responsable ve las de sus DIRECTOS solo si
--    (a) las asignó él, o (b) la persona las marcó `visible` y ya confirmó a
--    ese responsable (`responsables.confirmado`).
--  * Asignar, validar, devolver y retirar pasan por funciones (security definer)
--    que verifican la relación en el servidor. Desde la web no se puede escribir
--    asignada_por / validada_* / motivo_devolucion ni cambiar fecha y prioridad
--    de una tarea asignada (lo impone un trigger).
--  * Una tarea validada queda cerrada para su dueño.

alter table public.tareas
  add column if not exists asignada_por      uuid references auth.users(id) on delete set null,
  add column if not exists visible           boolean not null default false,
  add column if not exists validada_por      uuid references auth.users(id) on delete set null,
  add column if not exists validada_at       bigint  not null default 0,
  add column if not exists motivo_devolucion text    not null default '',
  add column if not exists devuelta_at       bigint  not null default 0;

alter table public.responsables
  add column if not exists confirmado boolean not null default false;
-- Los vínculos que ya existían todavía no tienen nada compartido: se dan por confirmados.
update public.responsables set confirmado = true;

create index if not exists tareas_user_idx on public.tareas (user_id);

-- ---------- visibilidad ----------

create or replace function public.ve_tarea_ajena(p_user uuid, p_asignada_por uuid, p_visible boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.responsables r
    where r.responsable_id = auth.uid() and r.persona_id = p_user
      and (p_asignada_por = auth.uid() or (p_visible and r.confirmado))
  );
$$;

drop policy if exists "dueño lee" on public.tareas;
create policy "dueño o responsable lee" on public.tareas for select
  using (auth.uid() = user_id or public.ve_tarea_ajena(user_id, asignada_por, visible));

-- Las tareas asignadas por un responsable no las borra la persona (las retira quien asignó).
drop policy if exists "dueño borra" on public.tareas;
create policy "dueño borra" on public.tareas for delete
  using (auth.uid() = user_id and asignada_por is null);

-- Nombres: cada uno ve a sus responsables y a sus directos.
create policy "ve a su equipo" on public.perfiles for select
  using (exists (
    select 1 from public.responsables r
    where (r.responsable_id = auth.uid() and r.persona_id = perfiles.id)
       or (r.persona_id = auth.uid() and r.responsable_id = perfiles.id)
  ));

-- ---------- candado de columnas ----------

create or replace function public.tareas_proteger()
returns trigger language plpgsql as $$
begin
  -- Las funciones security definer corren como su dueño: pasan sin restricción.
  if current_user not in ('authenticated', 'anon') then return new; end if;

  if tg_op = 'INSERT' then
    new.asignada_por := null; new.validada_por := null; new.validada_at := 0;
    new.motivo_devolucion := ''; new.devuelta_at := 0;
    return new;
  end if;

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
  return new;
end $$;

drop trigger if exists tareas_proteger_ins on public.tareas;
drop trigger if exists tareas_proteger_upd on public.tareas;
create trigger tareas_proteger_ins before insert on public.tareas
  for each row execute function public.tareas_proteger();
create trigger tareas_proteger_upd before update on public.tareas
  for each row execute function public.tareas_proteger();

-- ---------- acciones del responsable ----------

create or replace function public.asignar_tarea(
  p_persona uuid, p_text text, p_prio text default '', p_due text default '', p_notes text default ''
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
  select coalesce(max(ord), 0) + 1000 into v_ord from tareas where user_id = p_persona and status = 'pendiente';
  insert into tareas (user_id, text, status, prio, due, notes, ord, created_at, status_at, asignada_por, visible)
  values (p_persona, p_text, 'pendiente', coalesce(p_prio, ''), coalesce(p_due, ''),
          left(coalesce(p_notes, ''), 5000), v_ord, v_now, v_now, auth.uid(), true)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.validar_tarea(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare t tareas%rowtype;
begin
  select * into t from tareas where id = p_id for update;
  if not found or not ve_tarea_ajena(t.user_id, t.asignada_por, t.visible) then
    raise exception 'No podés validar esta tarea.';
  end if;
  if t.status <> 'completado' then raise exception 'La tarea todavía no está completada.'; end if;
  if t.validada_por is not null then return; end if;
  update tareas set validada_por = auth.uid(), validada_at = (extract(epoch from now()) * 1000)::bigint,
    motivo_devolucion = '' where id = p_id;
end $$;

create or replace function public.devolver_tarea(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare t tareas%rowtype; v_now bigint := (extract(epoch from now()) * 1000)::bigint;
begin
  p_motivo := btrim(coalesce(p_motivo, ''));
  if char_length(p_motivo) = 0 or char_length(p_motivo) > 500 then raise exception 'Escribí el motivo (hasta 500 caracteres).'; end if;
  select * into t from tareas where id = p_id for update;
  if not found or not ve_tarea_ajena(t.user_id, t.asignada_por, t.visible) then
    raise exception 'No podés devolver esta tarea.';
  end if;
  if t.status <> 'completado' then raise exception 'La tarea no está completada.'; end if;
  update tareas set status = 'proceso', done_at = 0, status_at = v_now,
    validada_por = null, validada_at = 0, motivo_devolucion = p_motivo, devuelta_at = v_now,
    avances = avances || jsonb_build_array(jsonb_build_object('t', v_now, 'x', 'Devuelta: ' || p_motivo))
  where id = p_id;
end $$;

create or replace function public.retirar_tarea(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from tareas where id = p_id and asignada_por = auth.uid();
  if not found then raise exception 'Solo podés retirar tareas que asignaste vos.'; end if;
end $$;

create or replace function public.confirmar_responsables()
returns void language sql security definer set search_path = public as $$
  update responsables set confirmado = true where persona_id = auth.uid() and not confirmado;
$$;

revoke all on function public.ve_tarea_ajena(uuid, uuid, boolean), public.asignar_tarea(uuid, text, text, text, text),
  public.validar_tarea(uuid), public.devolver_tarea(uuid, text), public.retirar_tarea(uuid),
  public.confirmar_responsables() from public, anon;
grant execute on function public.ve_tarea_ajena(uuid, uuid, boolean), public.asignar_tarea(uuid, text, text, text, text),
  public.validar_tarea(uuid), public.devolver_tarea(uuid, text), public.retirar_tarea(uuid),
  public.confirmar_responsables() to authenticated;
