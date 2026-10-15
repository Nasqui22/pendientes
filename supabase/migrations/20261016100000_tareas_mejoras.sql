-- Mejoras de tareas: comentarios, subtarea que se tilda sola, tareas recurrentes y archivo.
-- Solo agrega tablas, columnas con valor por defecto y triggers; no modifica datos existentes.

-- ---------- permisos mínimos para tablas nuevas ----------
alter default privileges in schema public revoke truncate, references, trigger on tables from authenticated;

-- ---------- comentarios ----------
-- Quien puede ver una tarea (dueño, responsables que la ven, quien la delegó) ve y escribe su hilo.
create or replace function public.puede_ver_tarea(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.tareas t
    where t.id = p_id
      and (t.user_id = auth.uid()
           or public.ve_tarea_ajena(t.user_id, t.asignada_por, t.visible)
           or t.delegada_por = auth.uid())
  );
$$;
revoke all on function public.puede_ver_tarea(uuid) from public, anon;
grant execute on function public.puede_ver_tarea(uuid) to authenticated;

create table if not exists public.comentarios (
  id         uuid primary key default gen_random_uuid(),
  tarea_id   uuid not null references public.tareas(id) on delete cascade,
  autor_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  texto      text not null check (char_length(btrim(texto)) between 1 and 1000),
  created_at bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists comentarios_tarea_idx on public.comentarios (tarea_id, created_at);
revoke all on public.comentarios from anon;
revoke truncate, references, trigger on public.comentarios from authenticated;

alter table public.comentarios enable row level security;
create policy "ve comentarios de tareas que ve" on public.comentarios for select
  using (public.puede_ver_tarea(tarea_id));
create policy "comenta en tareas que ve" on public.comentarios for insert
  with check (autor_id = auth.uid() and public.puede_ver_tarea(tarea_id));
create policy "borra sus comentarios" on public.comentarios for delete
  using (autor_id = auth.uid());

alter publication supabase_realtime add table public.comentarios;

-- Límites de uso (se agrega la rama de comentarios).
create or replace function public.limites_uso()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_now bigint := (extract(epoch from now()) * 1000)::bigint; n bigint;
begin
  if tg_table_name = 'tareas' then
    select count(*) into n from tareas where user_id = new.user_id;
    if n >= 3000 then raise exception 'Alcanzaste el máximo de tareas (3000).'; end if;
    if new.asignada_por is not null then
      select count(*) into n from tareas where asignada_por = new.asignada_por and created_at > v_now - 3600000;
      if n >= 60 then raise exception 'Demasiadas tareas asignadas en la última hora. Probá más tarde.'; end if;
    end if;
  elsif tg_table_name = 'delegaciones' then
    select count(*) into n from delegaciones where de_id = new.de_id and created_at > v_now - 3600000;
    if n >= 30 then raise exception 'Demasiadas solicitudes en la última hora. Probá más tarde.'; end if;
    select count(*) into n from delegaciones where de_id = new.de_id and estado = 'pendiente';
    if n >= 50 then raise exception 'Tenés demasiadas solicitudes pendientes.'; end if;
  elsif tg_table_name = 'libros' then
    select count(*) into n from libros where user_id = new.user_id;
    if n >= 200 then raise exception 'Alcanzaste el máximo de libros (200).'; end if;
  elsif tg_table_name = 'equipo_proyectos' then
    select count(*) into n from equipo_proyectos where lider_id = new.lider_id;
    if n >= 50 then raise exception 'Alcanzaste el máximo de proyectos (50).'; end if;
  elsif tg_table_name = 'proyectos' then
    select count(*) into n from proyectos where user_id = new.user_id;
    if n >= 100 then raise exception 'Alcanzaste el máximo de proyectos (100).'; end if;
  elsif tg_table_name = 'comentarios' then
    select count(*) into n from comentarios where tarea_id = new.tarea_id;
    if n >= 500 then raise exception 'Esta tarea alcanzó el máximo de comentarios (500).'; end if;
    select count(*) into n from comentarios where autor_id = new.autor_id and created_at > v_now - 3600000;
    if n >= 120 then raise exception 'Demasiados comentarios en la última hora. Probá más tarde.'; end if;
  end if;
  return new;
end $$;
revoke execute on function public.limites_uso() from public, anon, authenticated;
drop trigger if exists limites_uso_t on public.comentarios;
create trigger limites_uso_t before insert on public.comentarios
  for each row execute function public.limites_uso();

-- ---------- columnas nuevas de tareas ----------
alter table public.tareas
  add column if not exists recurrencia text not null default ''
    check (recurrencia in ('', 'diaria', 'semanal', 'mensual')),
  add column if not exists siguiente_id uuid references public.tareas(id) on delete set null,
  add column if not exists archivada boolean not null default false;

-- siguiente_id lo escribe solo el servidor (candado de columnas).
create or replace function public.tareas_proteger()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;

  if tg_op = 'INSERT' then
    new.asignada_por := null; new.validada_por := null; new.validada_at := 0;
    new.motivo_devolucion := ''; new.devuelta_at := 0; new.delegada_por := null; new.siguiente_id := null;
  else
    new.user_id := old.user_id;
    new.asignada_por := old.asignada_por;
    new.delegada_por := old.delegada_por;
    new.siguiente_id := old.siguiente_id;
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

-- Una tarea solo se archiva si está completada; al reabrirla vuelve al tablero.
create or replace function public.tareas_normalizar()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status <> 'completado' then new.archivada := false; end if;
  return new;
end $$;
revoke execute on function public.tareas_normalizar() from public, anon, authenticated;
drop trigger if exists tareas_normalizar_t on public.tareas;
create trigger tareas_normalizar_t before insert or update on public.tareas
  for each row execute function public.tareas_normalizar();

-- ---------- subtarea que se tilda sola ----------
-- Al completar (o reabrir) una tarea creada por una delegación aceptada, se actualiza la subtarea
-- de origen en la tarea de quien la pasó.
create or replace function public.tareas_sincronizar_delegada()
returns trigger language plpgsql security definer set search_path = public as $$
declare d public.delegaciones%rowtype; v boolean;
begin
  if new.status is not distinct from old.status or new.delegada_por is null then return new; end if;
  select * into d from public.delegaciones where nueva_tarea_id = new.id;
  if not found or d.tarea_id is null then return new; end if;
  v := (new.status = 'completado');
  update public.tareas set subs = coalesce((
      select jsonb_agg(case when e->>'t' = d.texto then jsonb_set(e, '{d}', to_jsonb(v)) else e end order by n)
      from jsonb_array_elements(subs) with ordinality as x(e, n)), '[]'::jsonb)
    where id = d.tarea_id;
  return new;
end $$;
revoke execute on function public.tareas_sincronizar_delegada() from public, anon, authenticated;
drop trigger if exists tareas_sincronizar_delegada_t on public.tareas;
create trigger tareas_sincronizar_delegada_t after update of status on public.tareas
  for each row execute function public.tareas_sincronizar_delegada();

-- ---------- tareas recurrentes ----------
-- Al completar una tarea propia con recurrencia, se crea la siguiente (una sola vez por tarea).
create or replace function public.tareas_recurrir()
returns trigger language plpgsql security definer set search_path = public as $$
declare stp interval; base date; nxt date; nid uuid; v_now bigint := (extract(epoch from now()) * 1000)::bigint; v_ord bigint; v_due text := '';
begin
  if new.status <> 'completado' or old.status = 'completado' then return new; end if;
  if new.recurrencia = '' or new.siguiente_id is not null or new.asignada_por is not null or new.delegada_por is not null then return new; end if;
  stp := case new.recurrencia when 'diaria' then interval '1 day' when 'semanal' then interval '7 days' else interval '1 month' end;
  if new.due ~ '^\d{4}-\d{2}-\d{2}$' then
    base := new.due::date; nxt := (base + stp)::date;
    while nxt <= current_date loop nxt := (nxt + stp)::date; end loop;
    v_due := to_char(nxt, 'YYYY-MM-DD');
  end if;
  begin
    select coalesce(max(ord), 0) + 1000 into v_ord from public.tareas where user_id = new.user_id and status = 'pendiente';
    insert into public.tareas (user_id, text, status, prio, due, notes, subs, ord, created_at, status_at, labels, visible, proyecto_id, equipo_proyecto_id, recurrencia)
    values (new.user_id, new.text, 'pendiente', new.prio, v_due, new.notes,
            coalesce((select jsonb_agg(jsonb_set(e, '{d}', 'false'::jsonb)) from jsonb_array_elements(new.subs) e), '[]'::jsonb),
            v_ord, v_now, v_now, new.labels, new.visible, new.proyecto_id, new.equipo_proyecto_id, new.recurrencia)
    returning id into nid;
    update public.tareas set siguiente_id = nid where id = new.id;
  exception when others then
    null; -- un límite o dato raro no debe impedir completar la tarea
  end;
  return new;
end $$;
revoke execute on function public.tareas_recurrir() from public, anon, authenticated;
drop trigger if exists tareas_recurrir_t on public.tareas;
create trigger tareas_recurrir_t after update of status on public.tareas
  for each row execute function public.tareas_recurrir();
