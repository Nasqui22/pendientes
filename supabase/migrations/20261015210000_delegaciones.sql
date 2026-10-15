-- Delegar subtareas entre compañeros (personas con al menos un responsable en común).
-- Quien delega propone una subtarea de una tarea propia; el compañero la acepta
-- (se crea una tarea suya) o la rechaza. Todo pasa por funciones del servidor:
-- la tabla es de solo lectura desde la web.

create or replace function public.es_companero(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p is not null and p <> auth.uid() and exists (
    select 1 from public.responsables a join public.responsables b on a.responsable_id = b.responsable_id
    where a.persona_id = auth.uid() and b.persona_id = p
  );
$$;

create policy "ve a sus compañeros" on public.perfiles for select using (public.es_companero(id));

create or replace function public.mis_companeros()
returns table (id uuid, nombre text) language sql stable security definer set search_path = public as $$
  select distinct p.id, coalesce(nullif(p.nombre, ''), p.email)
  from public.responsables a
  join public.responsables b on a.responsable_id = b.responsable_id and b.persona_id <> a.persona_id
  join public.perfiles p on p.id = b.persona_id
  where a.persona_id = auth.uid() and p.activo;
$$;

create table if not exists public.delegaciones (
  id              uuid primary key default gen_random_uuid(),
  de_id           uuid not null references auth.users(id) on delete cascade,
  a_id            uuid not null references auth.users(id) on delete cascade,
  tarea_id        uuid references public.tareas(id) on delete set null,
  tarea_texto     text not null default '',
  texto           text not null check (char_length(btrim(texto)) between 1 and 200),
  estado          text not null default 'pendiente' check (estado in ('pendiente', 'aceptada', 'rechazada')),
  motivo          text not null default '',
  nueva_tarea_id  uuid references public.tareas(id) on delete set null,
  created_at      bigint not null default (extract(epoch from now()) * 1000)::bigint,
  resuelta_at     bigint not null default 0,
  visto_por_de    boolean not null default false,
  check (de_id <> a_id)
);
create index if not exists delegaciones_a_idx on public.delegaciones (a_id, estado);
create index if not exists delegaciones_de_idx on public.delegaciones (de_id);

alter table public.delegaciones enable row level security;
create policy "ve las suyas" on public.delegaciones for select using (auth.uid() = de_id or auth.uid() = a_id);
-- Sin políticas de escritura: solo las funciones de abajo escriben.

alter publication supabase_realtime add table public.delegaciones;

create or replace function public.delegar_subtarea(p_tarea uuid, p_texto text, p_a uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare t tareas%rowtype; v_id uuid;
begin
  select * into t from tareas where id = p_tarea and user_id = auth.uid();
  if not found then raise exception 'Solo podés delegar subtareas de tus tareas.'; end if;
  if not es_companero(p_a) then raise exception 'Solo podés delegar a personas de tu mismo equipo.'; end if;
  if not exists (select 1 from jsonb_array_elements(t.subs) e where e->>'t' = p_texto and coalesce((e->>'d')::boolean, false) = false) then
    raise exception 'No encontré esa subtarea pendiente.';
  end if;
  if exists (select 1 from delegaciones where tarea_id = p_tarea and texto = p_texto and estado = 'pendiente') then
    raise exception 'Esa subtarea ya está pendiente de respuesta.';
  end if;
  insert into delegaciones (de_id, a_id, tarea_id, tarea_texto, texto)
  values (auth.uid(), p_a, p_tarea, t.text, left(p_texto, 200)) returning id into v_id;
  return v_id;
end $$;

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
    insert into tareas (user_id, text, status, notes, ord, created_at, status_at)
    values (auth.uid(), d.texto, 'pendiente',
            'Subtarea de «' || d.tarea_texto || '», pasada por ' || coalesce(v_nombre, 'un compañero') || '.',
            v_ord, v_now, v_now)
    returning id into v_nueva;
    update delegaciones set estado = 'aceptada', nueva_tarea_id = v_nueva, resuelta_at = v_now where id = p_id;
  else
    update delegaciones set estado = 'rechazada', motivo = left(btrim(coalesce(p_motivo, '')), 300), resuelta_at = v_now where id = p_id;
  end if;
end $$;

create or replace function public.cancelar_delegacion(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from delegaciones where id = p_id and de_id = auth.uid() and estado = 'pendiente';
  if not found then raise exception 'No se puede cancelar esa solicitud.'; end if;
end $$;

create or replace function public.marcar_delegaciones_vistas()
returns void language sql security definer set search_path = public as $$
  update delegaciones set visto_por_de = true where de_id = auth.uid() and estado <> 'pendiente' and not visto_por_de;
$$;

revoke all on function public.es_companero(uuid), public.mis_companeros(), public.delegar_subtarea(uuid, text, uuid),
  public.responder_delegacion(uuid, boolean, text), public.cancelar_delegacion(uuid), public.marcar_delegaciones_vistas()
  from public, anon;
grant execute on function public.es_companero(uuid), public.mis_companeros(), public.delegar_subtarea(uuid, text, uuid),
  public.responder_delegacion(uuid, boolean, text), public.cancelar_delegacion(uuid), public.marcar_delegaciones_vistas()
  to authenticated;
