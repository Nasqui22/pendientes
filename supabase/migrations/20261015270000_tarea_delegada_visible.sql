-- Las tareas que nacen de una subtarea aceptada (delegación) quedan siempre visibles:
-- las ven los responsables de quien la aceptó y quien se la pasó. La persona no puede
-- dejarlas privadas ni borrarlas (borrarla ocultaría el estado).

alter table public.tareas
  add column if not exists delegada_por uuid references auth.users(id) on delete set null;
create index if not exists tareas_delegada_idx on public.tareas (delegada_por) where delegada_por is not null;

-- Tareas ya creadas por aceptaciones anteriores.
update public.tareas t set delegada_por = d.de_id, visible = true
  from public.delegaciones d where d.nueva_tarea_id = t.id and t.delegada_por is null;

-- Candado de columnas (agrega delegada_por y fuerza visible).
create or replace function public.tareas_proteger()
returns trigger language plpgsql set search_path = public as $$
begin
  -- Las funciones security definer corren como su dueño: pasan sin restricción.
  if current_user not in ('authenticated', 'anon') then return new; end if;

  if tg_op = 'INSERT' then
    new.asignada_por := null; new.validada_por := null; new.validada_at := 0;
    new.motivo_devolucion := ''; new.devuelta_at := 0; new.delegada_por := null;
  else
    new.user_id := old.user_id;
    new.asignada_por := old.asignada_por;
    new.delegada_por := old.delegada_por;
    new.validada_por := old.validada_por;
    new.validada_at := old.validada_at;
    new.motivo_devolucion := old.motivo_devolucion;
    new.devuelta_at := old.devuelta_at;

    if old.asignada_por is not null then
      new.due := old.due;
      new.prio := old.prio;
    end if;
    if old.delegada_por is not null then
      new.visible := true;
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
revoke execute on function public.tareas_proteger() from public, anon, authenticated;

-- Quien delegó ve esa tarea (solo esa), además de dueño y responsables.
drop policy if exists "dueño o responsable lee" on public.tareas;
create policy "dueño, responsable o quien la pasó lee" on public.tareas for select
  using (auth.uid() = user_id or public.ve_tarea_ajena(user_id, asignada_por, visible) or delegada_por = auth.uid());

drop policy if exists "dueño borra" on public.tareas;
create policy "dueño borra" on public.tareas for delete
  using (auth.uid() = user_id and asignada_por is null and delegada_por is null);

-- Aceptar crea la tarea marcada como delegada y visible.
create or replace function public.responder_delegacion(p_id uuid, p_acepta boolean, p_motivo text default '')
returns void language plpgsql security definer set search_path = public as $$
declare d delegaciones%rowtype; v_now bigint := (extract(epoch from now()) * 1000)::bigint;
        v_nueva uuid; v_nombre text; v_ord bigint;
begin
  select * into d from delegaciones where id = p_id and a_id = auth.uid() and estado = 'pendiente' for update;
  if not found then raise exception 'Esa solicitud ya no está pendiente.'; end if;
  if p_acepta then
    select coalesce(nullif(nombre, ''), email) into v_nombre from perfiles where id = d.de_id;
    select coalesce(max(ord), 0) + 1000 into v_ord from tareas where user_id = auth.uid() and status = 'pendiente';
    insert into tareas (user_id, text, status, notes, ord, created_at, status_at, visible, delegada_por)
    values (auth.uid(), d.texto, 'pendiente',
            'Subtarea de «' || d.tarea_texto || '», pasada por ' || coalesce(v_nombre, 'un compañero') || '.',
            v_ord, v_now, v_now, true, d.de_id)
    returning id into v_nueva;
    update delegaciones set estado = 'aceptada', nueva_tarea_id = v_nueva, resuelta_at = v_now where id = p_id;
  else
    update delegaciones set estado = 'rechazada', motivo = left(btrim(coalesce(p_motivo, '')), 300), resuelta_at = v_now where id = p_id;
  end if;
end $$;
