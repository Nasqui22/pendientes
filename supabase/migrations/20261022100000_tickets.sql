-- Tickets: módulo aparte para pedir cosas a un servicio con responsable (el primero es Merlin).
-- Solo crea tablas, funciones y triggers nuevos y amplía los grupos de avisos; no modifica datos existentes.

-- =====================================================================
-- 1) Servicios (catálogo). Sin acceso directo desde la web: se lee con servicios_lista().
-- =====================================================================
create table if not exists public.servicios (
  id             uuid primary key default gen_random_uuid(),
  clave          text not null unique check (clave ~ '^[a-z0-9_-]{2,30}$'),
  nombre         text not null check (char_length(btrim(nombre)) between 1 and 60),
  descripcion    text not null default '' check (char_length(descripcion) <= 300),
  responsable_id uuid references auth.users(id) on delete set null,
  activo         boolean not null default true,
  created_at     bigint not null default (extract(epoch from now()) * 1000)::bigint
);
revoke all on public.servicios from anon;
revoke truncate, references, trigger on public.servicios from authenticated;
alter table public.servicios enable row level security;

-- Merlin, con Santiago Risi como responsable (se busca por nombre; si no existe todavía queda sin responsable
-- y no se podrán crear tickets hasta asignarlo: update servicios set responsable_id = '<id>' where clave = 'merlin').
insert into public.servicios (clave, nombre, descripcion, responsable_id)
select 'merlin', 'Merlin', 'Pedidos, cambios y problemas de Merlin.',
       (select p.id from public.perfiles p where p.activo and lower(btrim(p.nombre)) = 'santiago risi' limit 1)
on conflict (clave) do nothing;

create or replace function public.es_responsable_servicio(p_servicio uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.servicios where id = p_servicio and responsable_id = auth.uid());
$$;
revoke all on function public.es_responsable_servicio(uuid) from public, anon;
grant execute on function public.es_responsable_servicio(uuid) to authenticated;

create or replace function public.servicios_lista()
returns table (id uuid, clave text, nombre text, descripcion text, responsable_id uuid, responsable_nombre text)
language sql stable security definer set search_path = public as $$
  select s.id, s.clave, s.nombre, s.descripcion, s.responsable_id,
         coalesce(nullif(p.nombre, ''), p.email, '') as responsable_nombre
  from public.servicios s left join public.perfiles p on p.id = s.responsable_id
  where s.activo and auth.uid() is not null
  order by s.nombre;
$$;
revoke all on function public.servicios_lista() from public, anon;
grant execute on function public.servicios_lista() to authenticated;

-- =====================================================================
-- 2) Tickets
-- =====================================================================
create table if not exists public.tickets (
  id                 uuid primary key default gen_random_uuid(),
  numero             bigint generated always as identity,
  servicio_id        uuid not null references public.servicios(id),
  solicitante_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  solicitante_nombre text not null default '',
  titulo             text not null check (char_length(btrim(titulo)) between 1 and 120),
  prioridad          text not null default 'media' check (prioridad in ('baja', 'media', 'alta', 'urgente')),
  contexto           text not null check (char_length(btrim(contexto)) between 1 and 2000),
  entorno_url        text not null check (entorno_url ~ '^https?://[^[:space:]]{3,}$' and char_length(entorno_url) <= 500),
  entorno_tipo       text not null check (entorno_tipo in ('desarrollo', 'pruebas', 'preproduccion', 'produccion', 'otro')),
  criticidad         text not null check (criticidad in ('baja', 'media', 'alta', 'critica')),
  caso_ejemplo       text not null check (char_length(btrim(caso_ejemplo)) between 1 and 4000),
  estado             text not null default 'nuevo' check (estado in ('nuevo', 'en_curso', 'resuelto', 'cerrado')),
  created_at         bigint not null default (extract(epoch from now()) * 1000)::bigint,
  updated_at         bigint not null default (extract(epoch from now()) * 1000)::bigint,
  resuelto_at        bigint not null default 0,
  cerrado_at         bigint not null default 0
);
create index if not exists tickets_solicitante_idx on public.tickets (solicitante_id, created_at desc);
create index if not exists tickets_servicio_idx on public.tickets (servicio_id, estado, created_at desc);

revoke all on public.tickets from anon;
revoke truncate, references, trigger, update, delete on public.tickets from authenticated;
-- Solo el contenido se edita directamente (y solo mientras el ticket está «nuevo»); el estado pasa por cambiar_estado_ticket.
grant update (titulo, prioridad, contexto, entorno_url, entorno_tipo, criticidad, caso_ejemplo) on public.tickets to authenticated;
alter table public.tickets enable row level security;
create policy "ve sus tickets o los de su servicio" on public.tickets for select
  using (solicitante_id = auth.uid() or public.es_responsable_servicio(servicio_id));
create policy "crea sus tickets" on public.tickets for insert with check (solicitante_id = auth.uid());
create policy "edita su ticket nuevo" on public.tickets for update
  using (solicitante_id = auth.uid() and estado = 'nuevo') with check (solicitante_id = auth.uid() and estado = 'nuevo');

create or replace function public.puede_ver_ticket(p_ticket uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.tickets t
    where t.id = p_ticket and (t.solicitante_id = auth.uid() or public.es_responsable_servicio(t.servicio_id)));
$$;
revoke all on function public.puede_ver_ticket(uuid) from public, anon;
grant execute on function public.puede_ver_ticket(uuid) to authenticated;

create or replace function public.tickets_preparar()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ms bigint := (extract(epoch from now()) * 1000)::bigint; v_resp uuid;
begin
  if tg_op = 'INSERT' then
    select responsable_id into v_resp from public.servicios where id = new.servicio_id and activo;
    if not found then raise exception 'El servicio no existe o está inactivo.'; end if;
    if v_resp is null then raise exception 'Este servicio todavía no tiene responsable.'; end if;
    new.estado := 'nuevo'; new.resuelto_at := 0; new.cerrado_at := 0;
    new.created_at := v_ms; new.updated_at := v_ms;
    new.solicitante_nombre := public.nombre_de(new.solicitante_id);
  else
    new.updated_at := v_ms;
  end if;
  return new;
end $$;
revoke execute on function public.tickets_preparar() from public, anon, authenticated;
drop trigger if exists tickets_preparar_t on public.tickets;
create trigger tickets_preparar_t before insert or update on public.tickets
  for each row execute function public.tickets_preparar();

-- Cambios de estado (las reglas viven en el servidor):
--   responsable: nuevo -> en_curso, nuevo|en_curso -> resuelto, resuelto -> en_curso
--   solicitante: nuevo|en_curso|resuelto -> cerrado (confirma o cancela), resuelto -> en_curso (reabre)
create or replace function public.cambiar_estado_ticket(p_ticket uuid, p_estado text)
returns void language plpgsql security definer set search_path = public as $$
declare t public.tickets; v_ms bigint := (extract(epoch from now()) * 1000)::bigint;
        v_sol boolean; v_resp boolean; v_ok boolean := false; v_para uuid; v_tipo text; v_titulo text;
begin
  if auth.uid() is null then raise exception 'Sin sesión.'; end if;
  select * into t from public.tickets where id = p_ticket for update;
  if not found then raise exception 'El ticket no existe.'; end if;
  v_sol := t.solicitante_id = auth.uid();
  v_resp := public.es_responsable_servicio(t.servicio_id);
  if not (v_sol or v_resp) then raise exception 'El ticket no existe.'; end if;
  if p_estado not in ('nuevo', 'en_curso', 'resuelto', 'cerrado') or p_estado = t.estado then
    raise exception 'Cambio de estado no válido.';
  end if;
  if v_resp then
    v_ok := (t.estado = 'nuevo' and p_estado = 'en_curso') or (t.estado in ('nuevo', 'en_curso') and p_estado = 'resuelto')
         or (t.estado = 'resuelto' and p_estado = 'en_curso');
  end if;
  if not v_ok and v_sol then
    v_ok := (t.estado in ('nuevo', 'en_curso', 'resuelto') and p_estado = 'cerrado') or (t.estado = 'resuelto' and p_estado = 'en_curso');
  end if;
  if not v_ok then raise exception 'No podés pasar este ticket de % a %.', t.estado, p_estado; end if;

  update public.tickets set estado = p_estado,
    resuelto_at = case when p_estado = 'resuelto' then v_ms when p_estado = 'en_curso' then 0 else resuelto_at end,
    cerrado_at = case when p_estado = 'cerrado' then v_ms else 0 end
  where id = p_ticket;

  -- Avisa a la otra parte.
  if auth.uid() = t.solicitante_id then
    select responsable_id into v_para from public.servicios where id = t.servicio_id;
  else
    v_para := t.solicitante_id;
  end if;
  v_tipo := case p_estado when 'en_curso' then (case when t.estado = 'resuelto' then 'ticket_reabierto' else 'ticket_en_curso' end)
                          when 'resuelto' then 'ticket_resuelto' else 'ticket_cerrado' end;
  v_titulo := case v_tipo when 'ticket_reabierto' then 'Reabrieron el ticket #' when 'ticket_en_curso' then 'Ticket en curso #'
                          when 'ticket_resuelto' then 'Resolvieron el ticket #' else 'Cerraron el ticket #' end || t.numero;
  perform public.notificar(v_para, auth.uid(), 'tickets', v_tipo, v_titulo, t.titulo, 'ticket', t.id);
end $$;
revoke all on function public.cambiar_estado_ticket(uuid, text) from public, anon;
grant execute on function public.cambiar_estado_ticket(uuid, text) to authenticated;

create or replace function public.trg_aviso_tickets()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_resp uuid;
begin
  select responsable_id into v_resp from public.servicios where id = new.servicio_id;
  perform public.notificar(v_resp, new.solicitante_id, 'tickets', 'ticket_nuevo',
    'Ticket nuevo #' || new.numero || ' · ' || new.prioridad, new.solicitante_nombre || ': ' || new.titulo, 'ticket', new.id);
  return new;
end $$;
revoke execute on function public.trg_aviso_tickets() from public, anon, authenticated;
drop trigger if exists trg_aviso_tickets_i on public.tickets;
create trigger trg_aviso_tickets_i after insert on public.tickets for each row execute function public.trg_aviso_tickets();

-- =====================================================================
-- 3) Comentarios del ticket (los escriben y leen solicitante y responsable)
-- =====================================================================
create table if not exists public.ticket_comentarios (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.tickets(id) on delete cascade,
  autor_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  autor_nombre text not null default '',
  texto       text not null check (char_length(btrim(texto)) between 1 and 2000),
  created_at  bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists ticket_comentarios_idx on public.ticket_comentarios (ticket_id, created_at);
revoke all on public.ticket_comentarios from anon;
revoke truncate, references, trigger, update, delete on public.ticket_comentarios from authenticated;
alter table public.ticket_comentarios enable row level security;
create policy "ve comentarios de sus tickets" on public.ticket_comentarios for select using (public.puede_ver_ticket(ticket_id));
create policy "comenta sus tickets" on public.ticket_comentarios for insert
  with check (autor_id = auth.uid() and public.puede_ver_ticket(ticket_id));

create or replace function public.ticket_comentarios_preparar()
returns trigger language plpgsql security definer set search_path = public as $$
declare t public.tickets; v_para uuid;
begin
  select * into t from public.tickets where id = new.ticket_id;
  if t.estado = 'cerrado' then raise exception 'El ticket está cerrado.'; end if;
  new.created_at := (extract(epoch from now()) * 1000)::bigint;
  new.autor_nombre := public.nombre_de(new.autor_id);
  return new;
end $$;
revoke execute on function public.ticket_comentarios_preparar() from public, anon, authenticated;
drop trigger if exists ticket_comentarios_preparar_t on public.ticket_comentarios;
create trigger ticket_comentarios_preparar_t before insert on public.ticket_comentarios
  for each row execute function public.ticket_comentarios_preparar();

create or replace function public.trg_aviso_ticket_comentarios()
returns trigger language plpgsql security definer set search_path = public as $$
declare t public.tickets; v_para uuid;
begin
  select * into t from public.tickets where id = new.ticket_id;
  if new.autor_id = t.solicitante_id then
    select responsable_id into v_para from public.servicios where id = t.servicio_id;
  else
    v_para := t.solicitante_id;
  end if;
  perform public.notificar(v_para, new.autor_id, 'tickets', 'ticket_comentario',
    'Comentario en el ticket #' || t.numero, new.autor_nombre || ': ' || new.texto, 'ticket', t.id);
  return new;
end $$;
revoke execute on function public.trg_aviso_ticket_comentarios() from public, anon, authenticated;
drop trigger if exists trg_aviso_ticket_comentarios_i on public.ticket_comentarios;
create trigger trg_aviso_ticket_comentarios_i after insert on public.ticket_comentarios
  for each row execute function public.trg_aviso_ticket_comentarios();

alter publication supabase_realtime add table public.tickets;
alter publication supabase_realtime add table public.ticket_comentarios;

-- =====================================================================
-- 4) Avisos: grupo «tickets» y agrupación de comentarios de ticket
-- =====================================================================
alter table public.notificaciones drop constraint if exists notificaciones_grupo_check;
alter table public.notificaciones add constraint notificaciones_grupo_check
  check (grupo in ('tareas', 'comentarios', 'biblioteca', 'proyectos', 'equipo', 'tickets'));
alter table public.notif_prefs drop constraint if exists notif_prefs_silenciadas_check;
alter table public.notif_prefs add constraint notif_prefs_silenciadas_check
  check (silenciadas <@ array['tareas', 'comentarios', 'biblioteca', 'proyectos', 'equipo', 'tickets']::text[]);

create or replace function public.notificar(
  p_para uuid, p_de uuid, p_grupo text, p_tipo text, p_titulo text, p_cuerpo text, p_ref_tipo text, p_ref_id uuid
) returns void language plpgsql security definer set search_path = public as $$
declare v_now bigint := (extract(epoch from now()) * 1000)::bigint; sil text[];
begin
  if p_para is null or p_para is not distinct from p_de then return; end if;
  if not exists (select 1 from public.perfiles where id = p_para and activo) then return; end if;
  select silenciadas into sil from public.notif_prefs where persona_id = p_para;
  if sil is not null and p_grupo = any (sil) then return; end if;
  if p_tipo in ('comentario', 'ticket_comentario') then
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

-- =====================================================================
-- 5) Límites de uso (se agregan las ramas de tickets y sus comentarios)
-- =====================================================================
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
  elsif tg_table_name = 'tickets' then
    select count(*) into n from tickets where solicitante_id = new.solicitante_id and created_at > v_now - 3600000;
    if n >= 10 then raise exception 'Demasiados tickets en la última hora. Probá más tarde.'; end if;
    select count(*) into n from tickets where solicitante_id = new.solicitante_id and estado <> 'cerrado';
    if n >= 100 then raise exception 'Tenés demasiados tickets abiertos.'; end if;
  elsif tg_table_name = 'ticket_comentarios' then
    select count(*) into n from ticket_comentarios where ticket_id = new.ticket_id;
    if n >= 300 then raise exception 'Este ticket alcanzó el máximo de comentarios (300).'; end if;
    select count(*) into n from ticket_comentarios where autor_id = new.autor_id and created_at > v_now - 3600000;
    if n >= 120 then raise exception 'Demasiados comentarios en la última hora. Probá más tarde.'; end if;
  end if;
  return new;
end $$;
revoke execute on function public.limites_uso() from public, anon, authenticated;
do $$ declare t text; begin
  foreach t in array array['tickets', 'ticket_comentarios'] loop
    execute format('drop trigger if exists limites_uso_t on public.%I', t);
    execute format('create trigger limites_uso_t before insert on public.%I for each row execute function public.limites_uso()', t);
  end loop;
end $$;
