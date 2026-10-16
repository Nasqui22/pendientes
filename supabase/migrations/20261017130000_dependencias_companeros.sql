-- Dependencias con tareas de compañeros (personas que comparten un responsable).
--  · "Depende de" una tarea pública de un compañero: se crea activa, no pide aprobación (solo te bloquea a vos).
--  · "Bloquea a" una tarea pública de un compañero: queda pendiente hasta que su dueño la acepte.
-- Solo se ven las tareas que su dueño dejó visibles (visible = true).
alter table public.tarea_dependencias
  add column if not exists estado text not null default 'activa' check (estado in ('activa', 'pendiente')),
  add column if not exists aprobador_id uuid references auth.users(id) on delete cascade;
create index if not exists tarea_dependencias_aprob_idx on public.tarea_dependencias (aprobador_id) where aprobador_id is not null;

-- La veo yo, o es una tarea pública de un compañero.
create or replace function public.ve_para_dependencia(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.tareas t
    where t.id = p_id
      and (public.puede_ver_tarea(t.id) or (t.visible and not t.archivada and public.es_companero(t.user_id)))
  );
$$;
revoke all on function public.ve_para_dependencia(uuid) from public, anon;
grant execute on function public.ve_para_dependencia(uuid) to authenticated;

drop policy if exists "ve dependencias de tareas que ve" on public.tarea_dependencias;
drop policy if exists "crea dependencias entre tareas que ve" on public.tarea_dependencias;
drop policy if exists "quita dependencias propias o de sus tareas" on public.tarea_dependencias;
create policy "ve dependencias de tareas que ve" on public.tarea_dependencias for select
  using ((estado = 'activa' or creada_por = auth.uid() or aprobador_id = auth.uid())
    and public.ve_para_dependencia(tarea_id) and public.ve_para_dependencia(bloqueada_por));
-- Las reglas finas (quién puede relacionar qué) las aplica el trigger dependencias_validar.
create policy "crea dependencias" on public.tarea_dependencias for insert
  with check (creada_por = auth.uid());
create policy "quita dependencias propias, de sus tareas o que debe aprobar" on public.tarea_dependencias for delete
  using (creada_por = auth.uid() or aprobador_id = auth.uid()
    or public.puede_gestionar_tarea(tarea_id) or public.puede_gestionar_tarea(bloqueada_por));

create or replace function public.dep_crea_ciclo(p_tarea uuid, p_bloq uuid)
returns boolean language sql stable security definer set search_path = public as $$
  with recursive cadena(id) as (
    select p_bloq
    union
    select d.bloqueada_por from public.tarea_dependencias d join cadena c on d.tarea_id = c.id where d.estado = 'activa'
  )
  select exists (select 1 from cadena where id = p_tarea);
$$;
revoke all on function public.dep_crea_ciclo(uuid, uuid) from public, anon, authenticated;

create or replace function public.dependencias_validar()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_now bigint := (extract(epoch from now()) * 1000)::bigint; n bigint; tt public.tareas%rowtype; tb public.tareas%rowtype;
begin
  new.estado := 'activa'; new.aprobador_id := null;
  select * into tt from public.tareas where id = new.tarea_id;
  select * into tb from public.tareas where id = new.bloqueada_por;
  if auth.uid() is not null then
    new.creada_por := auth.uid();
    if public.puede_ver_tarea(tt.id) and public.puede_ver_tarea(tb.id)
       and (public.puede_gestionar_tarea(tt.id) or public.puede_gestionar_tarea(tb.id)) then
      null;                                                     -- tareas propias o del equipo que dirige
    elsif tt.user_id = auth.uid() and tb.visible and not tb.archivada and public.es_companero(tb.user_id) then
      null;                                                     -- mi tarea depende de una pública de un compañero
    elsif tb.user_id = auth.uid() and tb.visible and not tb.archivada
          and tt.visible and not tt.archivada and public.es_companero(tt.user_id) then
      new.estado := 'pendiente'; new.aprobador_id := tt.user_id; -- mi tarea bloquearía la suya: él decide
    else
      raise exception 'No podés relacionar estas tareas.' using errcode = 'P0001';
    end if;
  end if;
  if new.estado = 'activa' and public.dep_crea_ciclo(new.tarea_id, new.bloqueada_por) then
    raise exception 'Esa relación crearía un círculo: una de las tareas ya depende de la otra.' using errcode = 'P0001';
  end if;
  select count(*) into n from public.tarea_dependencias where tarea_id = new.tarea_id;
  if n >= 20 then raise exception 'Una tarea puede depender de hasta 20 tareas.' using errcode = 'P0001'; end if;
  select count(*) into n from public.tarea_dependencias where creada_por = new.creada_por and created_at > v_now - 3600000;
  if n >= 100 then raise exception 'Demasiadas relaciones en la última hora. Probá más tarde.' using errcode = 'P0001'; end if;
  if new.estado = 'pendiente' then
    select count(*) into n from public.tarea_dependencias where creada_por = new.creada_por and estado = 'pendiente';
    if n >= 30 then raise exception 'Tenés demasiados pedidos pendientes.' using errcode = 'P0001'; end if;
  end if;
  return new;
end $$;
revoke execute on function public.dependencias_validar() from public, anon, authenticated;

-- Avisos (sin revelar títulos de tareas privadas).
create or replace function public.dependencias_avisar()
returns trigger language plpgsql security definer set search_path = public as $$
declare tt public.tareas%rowtype; tb public.tareas%rowtype;
begin
  select * into tt from public.tareas where id = new.tarea_id;
  select * into tb from public.tareas where id = new.bloqueada_por;
  if new.estado = 'pendiente' then
    perform public.notificar(new.aprobador_id, new.creada_por, 'tareas', 'dependencia_pedida',
      public.nombre_de(new.creada_por) || ' pide que su tarea bloquee una tuya', tb.text || ' → «' || tt.text || '»', 'tarea', tt.id);
  elsif tt.user_id = new.creada_por and tb.user_id <> new.creada_por then
    perform public.notificar(tb.user_id, new.creada_por, 'tareas', 'dependencia_nueva',
      public.nombre_de(new.creada_por) || ' depende de una tarea tuya', tb.text, 'tarea', tb.id);
  end if;
  return new;
end $$;
revoke execute on function public.dependencias_avisar() from public, anon, authenticated;
drop trigger if exists dependencias_avisar_t on public.tarea_dependencias;
create trigger dependencias_avisar_t after insert on public.tarea_dependencias
  for each row execute function public.dependencias_avisar();

-- El dueño de la tarea a bloquear acepta o rechaza.
create or replace function public.responder_dependencia(p_id uuid, p_acepta boolean)
returns void language plpgsql security definer set search_path = public as $$
declare d public.tarea_dependencias%rowtype; tt public.tareas%rowtype; tb public.tareas%rowtype;
begin
  select * into d from public.tarea_dependencias where id = p_id for update;
  if not found or d.estado <> 'pendiente' or d.aprobador_id is distinct from auth.uid() then
    raise exception 'No hay un pedido para responder.' using errcode = 'P0001';
  end if;
  select * into tt from public.tareas where id = d.tarea_id;
  select * into tb from public.tareas where id = d.bloqueada_por;
  if p_acepta then
    if public.dep_crea_ciclo(d.tarea_id, d.bloqueada_por) then
      raise exception 'Esa relación crearía un círculo: una de las tareas ya depende de la otra.' using errcode = 'P0001';
    end if;
    update public.tarea_dependencias set estado = 'activa' where id = p_id;
  else
    delete from public.tarea_dependencias where id = p_id;
  end if;
  perform public.notificar(d.creada_por, auth.uid(), 'tareas', case when p_acepta then 'dependencia_aceptada' else 'dependencia_rechazada' end,
    public.nombre_de(auth.uid()) || case when p_acepta then ' aceptó que tu tarea bloquee la suya' else ' rechazó que tu tarea bloquee la suya' end,
    tb.text, 'tarea', tb.id);
end $$;
revoke all on function public.responder_dependencia(uuid, boolean) from public, anon;
grant execute on function public.responder_dependencia(uuid, boolean) to authenticated;

-- Tareas públicas de mis compañeros (para elegir con cuál relacionar) y datos de las ya relacionadas.
create or replace function public.tareas_de_companeros()
returns table (id uuid, user_id uuid, text text, status text, prio text, due text, equipo_proyecto_id uuid, done_at bigint)
language sql stable security definer set search_path = public as $$
  select t.id, t.user_id, t.text, t.status, t.prio, t.due, t.equipo_proyecto_id, t.done_at
  from public.tareas t
  where t.visible and not t.archivada and public.es_companero(t.user_id)
  order by t.created_at desc limit 1000;
$$;
create or replace function public.dependencias_info(p_ids uuid[])
returns table (id uuid, user_id uuid, text text, status text, prio text, due text, equipo_proyecto_id uuid, done_at bigint)
language sql stable security definer set search_path = public as $$
  select t.id, t.user_id, t.text, t.status, t.prio, t.due, t.equipo_proyecto_id, t.done_at
  from public.tareas t
  where t.id = any (p_ids[1:200]) and public.ve_para_dependencia(t.id);
$$;
revoke all on function public.tareas_de_companeros(), public.dependencias_info(uuid[]) from public, anon;
grant execute on function public.tareas_de_companeros(), public.dependencias_info(uuid[]) to authenticated;
