-- Proyectos de equipo (fechas, estado e hitos) y centro de notificaciones.
-- Solo agrega columnas con valor por defecto, tablas nuevas y triggers; no modifica datos existentes.

-- =====================================================================
-- 1) Proyectos de equipo: fechas, estado e hitos
-- =====================================================================
alter table public.equipo_proyectos
  add column if not exists inicio text not null default '' check (inicio = '' or inicio ~ '^\d{4}-\d{2}-\d{2}$'),
  add column if not exists fin    text not null default '' check (fin = ''    or fin    ~ '^\d{4}-\d{2}-\d{2}$'),
  add column if not exists estado text not null default 'activo' check (estado in ('activo', 'pausado', 'cerrado'));

create table if not exists public.proyecto_hitos (
  id          uuid primary key default gen_random_uuid(),
  proyecto_id uuid not null references public.equipo_proyectos(id) on delete cascade,
  titulo      text not null check (char_length(btrim(titulo)) between 1 and 120),
  fecha       text not null default '' check (fecha = '' or fecha ~ '^\d{4}-\d{2}-\d{2}$'),
  hecho       boolean not null default false,
  hecho_at    bigint not null default 0,
  orden       int not null default 0,
  created_at  bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists proyecto_hitos_idx on public.proyecto_hitos (proyecto_id, orden);
revoke all on public.proyecto_hitos from anon;
revoke truncate, references, trigger on public.proyecto_hitos from authenticated;
alter table public.proyecto_hitos enable row level security;
create policy "ve hitos de sus proyectos" on public.proyecto_hitos for select
  using (public.es_lider_de_proyecto(proyecto_id) or public.es_miembro_de_proyecto(proyecto_id));
create policy "lider crea hitos" on public.proyecto_hitos for insert with check (public.es_lider_de_proyecto(proyecto_id));
create policy "lider edita hitos" on public.proyecto_hitos for update
  using (public.es_lider_de_proyecto(proyecto_id)) with check (public.es_lider_de_proyecto(proyecto_id));
create policy "lider borra hitos" on public.proyecto_hitos for delete using (public.es_lider_de_proyecto(proyecto_id));

-- Fecha en que se marcó hecho; máximo 30 hitos por proyecto.
create or replace function public.hitos_normalizar()
returns trigger language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if tg_op = 'INSERT' then
    select count(*) into n from public.proyecto_hitos where proyecto_id = new.proyecto_id;
    if n >= 30 then raise exception 'Un proyecto admite hasta 30 hitos.'; end if;
  end if;
  if new.hecho and (tg_op = 'INSERT' or not old.hecho) then new.hecho_at := (extract(epoch from now()) * 1000)::bigint; end if;
  if not new.hecho then new.hecho_at := 0; end if;
  return new;
end $$;
revoke execute on function public.hitos_normalizar() from public, anon, authenticated;
drop trigger if exists hitos_normalizar_t on public.proyecto_hitos;
create trigger hitos_normalizar_t before insert or update on public.proyecto_hitos
  for each row execute function public.hitos_normalizar();

-- =====================================================================
-- 2) Notificaciones
-- =====================================================================
create table if not exists public.notificaciones (
  id         uuid primary key default gen_random_uuid(),
  para_id    uuid not null references auth.users(id) on delete cascade,
  de_id      uuid references auth.users(id) on delete set null,
  grupo      text not null check (grupo in ('tareas', 'comentarios', 'biblioteca', 'proyectos', 'equipo')),
  tipo       text not null,
  titulo     text not null,
  cuerpo     text not null default '',
  ref_tipo   text not null default '',
  ref_id     uuid,
  cantidad   int not null default 1,
  leida      boolean not null default false,
  created_at bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists notificaciones_para_idx on public.notificaciones (para_id, leida, created_at desc);
revoke all on public.notificaciones from anon;
revoke truncate, references, trigger, insert, update on public.notificaciones from authenticated;
grant update (leida) on public.notificaciones to authenticated;     -- solo se puede marcar como leída
alter table public.notificaciones enable row level security;
create policy "ve sus notificaciones" on public.notificaciones for select using (para_id = auth.uid());
create policy "marca sus notificaciones" on public.notificaciones for update using (para_id = auth.uid()) with check (para_id = auth.uid());
create policy "borra sus notificaciones" on public.notificaciones for delete using (para_id = auth.uid());
alter publication supabase_realtime add table public.notificaciones;

-- Qué grupos de avisos quiere silenciar cada persona.
create table if not exists public.notif_prefs (
  persona_id  uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  silenciadas text[] not null default '{}' check (silenciadas <@ array['tareas', 'comentarios', 'biblioteca', 'proyectos', 'equipo']::text[])
);
revoke all on public.notif_prefs from anon;
revoke truncate, references, trigger on public.notif_prefs from authenticated;
alter table public.notif_prefs enable row level security;
create policy "ve sus preferencias" on public.notif_prefs for select using (persona_id = auth.uid());
create policy "crea sus preferencias" on public.notif_prefs for insert with check (persona_id = auth.uid());
create policy "edita sus preferencias" on public.notif_prefs for update using (persona_id = auth.uid()) with check (persona_id = auth.uid());

-- Crea un aviso (respeta preferencias, no avisa a quien hizo la acción, agrupa comentarios y conserva los últimos 100).
create or replace function public.notificar(
  p_para uuid, p_de uuid, p_grupo text, p_tipo text, p_titulo text, p_cuerpo text, p_ref_tipo text, p_ref_id uuid
) returns void language plpgsql security definer set search_path = public as $$
declare v_now bigint := (extract(epoch from now()) * 1000)::bigint; sil text[];
begin
  if p_para is null or p_para is not distinct from p_de then return; end if;
  if not exists (select 1 from public.perfiles where id = p_para and activo) then return; end if;
  select silenciadas into sil from public.notif_prefs where persona_id = p_para;
  if sil is not null and p_grupo = any (sil) then return; end if;
  if p_tipo = 'comentario' then
    update public.notificaciones set cantidad = cantidad + 1, created_at = v_now, cuerpo = left(p_cuerpo, 200), de_id = p_de
      where para_id = p_para and tipo = p_tipo and ref_id = p_ref_id and not leida;
    if found then return; end if;
  end if;
  insert into public.notificaciones (para_id, de_id, grupo, tipo, titulo, cuerpo, ref_tipo, ref_id)
  values (p_para, p_de, p_grupo, p_tipo, left(p_titulo, 200), left(p_cuerpo, 200), p_ref_tipo, p_ref_id);
  delete from public.notificaciones where para_id = p_para
    and id in (select id from public.notificaciones where para_id = p_para order by created_at desc offset 100);
end $$;
revoke execute on function public.notificar(uuid, uuid, text, text, text, text, text, uuid) from public, anon, authenticated;

create or replace function public.nombre_de(p uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(nombre, ''), email, 'Alguien') from public.perfiles where id = p;
$$;
revoke execute on function public.nombre_de(uuid) from public, anon, authenticated;

-- Quiénes ven una tarea (mismas reglas que la visibilidad): dueño, quien la asignó, quien la pasó y responsables que la ven.
create or replace function public.destinatarios_tarea(p_tarea uuid)
returns table (id uuid) language sql stable security definer set search_path = public as $$
  select t.user_id from public.tareas t where t.id = p_tarea
  union select t.asignada_por from public.tareas t where t.id = p_tarea and t.asignada_por is not null
  union select t.delegada_por from public.tareas t where t.id = p_tarea and t.delegada_por is not null
  union select r.responsable_id from public.tareas t join public.responsables r on r.persona_id = t.user_id
        where t.id = p_tarea and (t.asignada_por = r.responsable_id or (t.visible and r.confirmado));
$$;
revoke execute on function public.destinatarios_tarea(uuid) from public, anon, authenticated;

-- Personas que pueden ver un libro (sin chequear quién pregunta; solo para uso interno de los triggers).
create or replace function public.audiencia_libro_ids(p_libro uuid)
returns table (id uuid) language sql stable security definer set search_path = public as $$
  select p.id from public.libros l, public.perfiles p
  where l.id = p_libro and p.activo and p.id <> l.user_id
    and ((l.alcance = 'equipo' and public.mismo_equipo(l.user_id, p.id))
      or (l.alcance = 'personas' and p.id = any (l.destinatarios) and public.mismo_equipo(l.user_id, p.id))
      or exists (
        select 1 from public.equipo_proyecto_libros pl
        join public.equipo_proyectos pr on pr.id = pl.proyecto_id
        join public.equipo_proyecto_miembros m on m.proyecto_id = pl.proyecto_id
        join public.responsables r on r.responsable_id = pr.lider_id and r.persona_id = m.persona_id
        where pl.libro_id = l.id and m.persona_id = p.id));
$$;
revoke execute on function public.audiencia_libro_ids(uuid) from public, anon, authenticated;

-- ---------- triggers de avisos ----------

create or replace function public.trg_aviso_tareas()
returns trigger language plpgsql security definer set search_path = public as $$
declare d uuid;
begin
  if tg_op = 'INSERT' then
    if new.asignada_por is not null then
      perform public.notificar(new.user_id, new.asignada_por, 'tareas', 'tarea_asignada', 'Te asignaron una tarea', new.text, 'tarea', new.id);
    end if;
    return new;
  end if;
  if old.validada_por is null and new.validada_por is not null then
    perform public.notificar(new.user_id, new.validada_por, 'tareas', 'tarea_validada', 'Validaron tu tarea', new.text, 'tarea', new.id);
  end if;
  if new.devuelta_at > old.devuelta_at then
    perform public.notificar(new.user_id, auth.uid(), 'tareas', 'tarea_devuelta', 'Te devolvieron una tarea', new.text || ' — ' || new.motivo_devolucion, 'tarea', new.id);
  end if;
  if old.status <> 'completado' and new.status = 'completado' and (new.visible or new.asignada_por is not null or new.delegada_por is not null) then
    for d in select id from public.destinatarios_tarea(new.id) loop
      if d <> new.user_id then
        perform public.notificar(d, new.user_id, 'tareas', 'tarea_completada', public.nombre_de(new.user_id) || ' completó una tarea', new.text, 'tarea', new.id);
      end if;
    end loop;
  end if;
  return new;
end $$;
revoke execute on function public.trg_aviso_tareas() from public, anon, authenticated;
drop trigger if exists trg_aviso_tareas_i on public.tareas;
drop trigger if exists trg_aviso_tareas_u on public.tareas;
create trigger trg_aviso_tareas_i after insert on public.tareas for each row execute function public.trg_aviso_tareas();
create trigger trg_aviso_tareas_u after update on public.tareas for each row execute function public.trg_aviso_tareas();

create or replace function public.trg_aviso_comentarios()
returns trigger language plpgsql security definer set search_path = public as $$
declare d uuid; v_texto text;
begin
  select text into v_texto from public.tareas where id = new.tarea_id;
  for d in select id from public.destinatarios_tarea(new.tarea_id) loop
    perform public.notificar(d, new.autor_id, 'comentarios', 'comentario', 'Comentario en «' || left(coalesce(v_texto, 'una tarea'), 60) || '»',
      public.nombre_de(new.autor_id) || ': ' || new.texto, 'tarea', new.tarea_id);
  end loop;
  return new;
end $$;
revoke execute on function public.trg_aviso_comentarios() from public, anon, authenticated;
drop trigger if exists trg_aviso_comentarios_i on public.comentarios;
create trigger trg_aviso_comentarios_i after insert on public.comentarios for each row execute function public.trg_aviso_comentarios();

create or replace function public.trg_aviso_libros()
returns trigger language plpgsql security definer set search_path = public as $$
declare d uuid; compartido boolean; pide boolean; nuevaver boolean;
begin
  compartido := new.alcance <> 'privado' and (tg_op = 'INSERT' or old.alcance = 'privado');
  pide := new.requiere_lectura and (tg_op = 'INSERT' or not old.requiere_lectura);
  nuevaver := tg_op = 'UPDATE' and new.requiere_lectura and new.version > old.version;
  if not (compartido or pide or nuevaver) or new.alcance = 'privado' then return new; end if;
  for d in select id from public.audiencia_libro_ids(new.id) loop
    if pide then
      perform public.notificar(d, new.user_id, 'biblioteca', 'lectura_pedida', 'Te piden leer un libro', new.titulo, 'libro', new.id);
    elsif nuevaver then
      perform public.notificar(d, new.user_id, 'biblioteca', 'libro_actualizado', 'Libro actualizado: confirmá de nuevo', new.titulo, 'libro', new.id);
    else
      perform public.notificar(d, new.user_id, 'biblioteca', 'libro_compartido', 'Nuevo libro para tu equipo', new.titulo, 'libro', new.id);
    end if;
  end loop;
  return new;
end $$;
revoke execute on function public.trg_aviso_libros() from public, anon, authenticated;
drop trigger if exists trg_aviso_libros_i on public.libros;
drop trigger if exists trg_aviso_libros_u on public.libros;
create trigger trg_aviso_libros_i after insert on public.libros for each row execute function public.trg_aviso_libros();
create trigger trg_aviso_libros_u after update on public.libros for each row execute function public.trg_aviso_libros();

create or replace function public.trg_aviso_proyecto_libros()
returns trigger language plpgsql security definer set search_path = public as $$
declare d uuid; v_titulo text; v_proy text; v_lider uuid;
begin
  select titulo into v_titulo from public.libros where id = new.libro_id;
  select nombre, lider_id into v_proy, v_lider from public.equipo_proyectos where id = new.proyecto_id;
  for d in select m.persona_id from public.equipo_proyecto_miembros m where m.proyecto_id = new.proyecto_id loop
    perform public.notificar(d, v_lider, 'biblioteca', 'libro_proyecto', 'Nuevo libro en el proyecto «' || v_proy || '»', v_titulo, 'libro', new.libro_id);
  end loop;
  return new;
end $$;
revoke execute on function public.trg_aviso_proyecto_libros() from public, anon, authenticated;
drop trigger if exists trg_aviso_proyecto_libros_i on public.equipo_proyecto_libros;
create trigger trg_aviso_proyecto_libros_i after insert on public.equipo_proyecto_libros for each row execute function public.trg_aviso_proyecto_libros();

create or replace function public.trg_aviso_proyecto_miembros()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_proy text; v_lider uuid;
begin
  select nombre, lider_id into v_proy, v_lider from public.equipo_proyectos where id = new.proyecto_id;
  perform public.notificar(new.persona_id, v_lider, 'proyectos', 'proyecto_asignado', 'Te sumaron a un proyecto', v_proy, 'proyecto', new.proyecto_id);
  return new;
end $$;
revoke execute on function public.trg_aviso_proyecto_miembros() from public, anon, authenticated;
drop trigger if exists trg_aviso_proyecto_miembros_i on public.equipo_proyecto_miembros;
create trigger trg_aviso_proyecto_miembros_i after insert on public.equipo_proyecto_miembros for each row execute function public.trg_aviso_proyecto_miembros();

create or replace function public.trg_aviso_hitos()
returns trigger language plpgsql security definer set search_path = public as $$
declare d uuid; v_proy text; v_lider uuid;
begin
  if not (new.hecho and not old.hecho) then return new; end if;
  select nombre, lider_id into v_proy, v_lider from public.equipo_proyectos where id = new.proyecto_id;
  for d in select m.persona_id from public.equipo_proyecto_miembros m where m.proyecto_id = new.proyecto_id loop
    perform public.notificar(d, v_lider, 'proyectos', 'hito_cumplido', 'Hito cumplido en «' || v_proy || '»', new.titulo, 'proyecto', new.proyecto_id);
  end loop;
  return new;
end $$;
revoke execute on function public.trg_aviso_hitos() from public, anon, authenticated;
drop trigger if exists trg_aviso_hitos_u on public.proyecto_hitos;
create trigger trg_aviso_hitos_u after update on public.proyecto_hitos for each row execute function public.trg_aviso_hitos();

create or replace function public.trg_aviso_responsables()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notificar(new.persona_id, new.responsable_id, 'equipo', 'responsable_nuevo',
    public.nombre_de(new.responsable_id) || ' es tu nuevo responsable', 'Todavía no ve tus tareas: revisá qué compartís y confirmá.', 'equipo', null);
  return new;
end $$;
revoke execute on function public.trg_aviso_responsables() from public, anon, authenticated;
drop trigger if exists trg_aviso_responsables_i on public.responsables;
create trigger trg_aviso_responsables_i after insert on public.responsables for each row execute function public.trg_aviso_responsables();
