-- Endurecimiento de seguridad.
--  1) Permisos mínimos: nada para `anon` y sin TRUNCATE/REFERENCES/TRIGGER para `authenticated`
--     (el acceso real lo gobiernan las políticas RLS).
--  2) Un admin no puede dar de alta un responsable ya "confirmado": la persona debe confirmarlo.
--  3) Funciones de trigger sin permiso de ejecución directo y con search_path fijo.
--  4) Validación de tareas en el servidor y límites de uso (anti-abuso).
--  5) Registro de acciones de administración (lo usa la Edge Function).

-- ---------- 1) permisos ----------
revoke all on all tables in schema public from anon;
revoke truncate, references, trigger on all tables in schema public from authenticated;
revoke all on all sequences in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on functions from anon;

-- ---------- 2) consentimiento ----------
drop policy if exists "admin asigna" on public.responsables;
create policy "admin asigna" on public.responsables for insert
  with check (public.es_admin() and confirmado = false);

-- ---------- 3) funciones ----------
alter function public.tareas_proteger() set search_path = public;
alter function public.libros_validar() set search_path = public;
revoke execute on function public.crear_perfil(), public.evitar_ciclo_responsables(),
  public.libros_validar(), public.tareas_proteger() from public, anon, authenticated;
revoke execute on function public.es_admin() from public, anon;

-- ---------- 4) validación y límites ----------
create or replace function public.tareas_validar()
returns trigger language plpgsql set search_path = public as $$
declare e jsonb;
begin
  if char_length(new.text) > 300 then raise exception 'El título admite hasta 300 caracteres.'; end if;
  if char_length(new.notes) > 10000 then raise exception 'Las notas admiten hasta 10000 caracteres.'; end if;
  if new.prio not in ('', 'alta', 'media', 'baja') then raise exception 'Prioridad inválida.'; end if;
  if new.due <> '' and new.due !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Fecha inválida.'; end if;
  if jsonb_typeof(new.labels) <> 'array' or jsonb_array_length(new.labels) > 8 then raise exception 'Hasta 8 etiquetas por tarea.'; end if;
  for e in select * from jsonb_array_elements(new.labels) loop
    if jsonb_typeof(e) <> 'string' or char_length(e #>> '{}') > 24 then raise exception 'Etiqueta inválida (hasta 24 caracteres).'; end if;
  end loop;
  if jsonb_typeof(new.subs) <> 'array' or jsonb_array_length(new.subs) > 100 then raise exception 'Hasta 100 subtareas por tarea.'; end if;
  for e in select * from jsonb_array_elements(new.subs) loop
    if jsonb_typeof(e) <> 'object' or jsonb_typeof(e->'t') <> 'string' or char_length(e->>'t') > 200 then
      raise exception 'Subtarea inválida (hasta 200 caracteres).';
    end if;
  end loop;
  if jsonb_typeof(new.avances) <> 'array' or jsonb_array_length(new.avances) > 300 then raise exception 'Hasta 300 avances por tarea.'; end if;
  for e in select * from jsonb_array_elements(new.avances) loop
    if jsonb_typeof(e) <> 'object' or jsonb_typeof(e->'x') <> 'string' or char_length(e->>'x') > 600 then
      raise exception 'Avance inválido (hasta 500 caracteres).';
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists tareas_validar_t on public.tareas;
create trigger tareas_validar_t before insert or update on public.tareas
  for each row execute function public.tareas_validar();
revoke execute on function public.tareas_validar() from public, anon, authenticated;

-- Límites de uso (cuentas y volumen), contados en el servidor.
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
  end if;
  return new;
end $$;
revoke execute on function public.limites_uso() from public, anon, authenticated;
do $$ declare t text; begin
  foreach t in array array['tareas', 'delegaciones', 'libros', 'equipo_proyectos', 'proyectos'] loop
    execute format('drop trigger if exists limites_uso_t on public.%I', t);
    execute format('create trigger limites_uso_t before insert on public.%I for each row execute function public.limites_uso()', t);
  end loop;
end $$;

-- ---------- 5) registro de acciones de administración ----------
create table if not exists public.admin_acciones (
  id         bigint generated always as identity primary key,
  admin_id   uuid not null,
  accion     text not null,
  objetivo   uuid,
  created_at timestamptz not null default now()
);
create index if not exists admin_acciones_idx on public.admin_acciones (admin_id, created_at desc);
alter table public.admin_acciones enable row level security;
revoke all on public.admin_acciones from anon, authenticated;  -- sin políticas: solo service_role
