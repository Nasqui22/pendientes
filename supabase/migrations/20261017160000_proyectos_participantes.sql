-- Proyectos de equipo con responsable, participantes y revisión.
--  · Cualquiera crea un proyecto y es su responsable (lider_id). Elige quiénes participan entre su equipo
--    (compañeros, su responsable y sus directos): ellos ven el proyecto, vinculan tareas y crean nuevas.
--  · El responsable de la persona que lo creó (su responsable de equipo) lo ve siempre y puede aceptarlo
--    o rechazarlo. Si no hace nada, el proyecto sigue activo. Rechazado: solo lo ven su responsable y quien
--    lo revisa, y no se le pueden vincular tareas nuevas; el responsable puede pedir una nueva revisión.
--  · Por defecto un proyecto ya NO es visible para todo el equipo: solo para quienes participan (se puede abrir).
alter table public.equipo_proyectos
  add column if not exists revision text not null default 'aceptado' check (revision in ('pendiente', 'aceptado', 'rechazado')),
  add column if not exists revisado_por uuid references auth.users(id) on delete set null,
  add column if not exists revisado_at bigint not null default 0,
  add column if not exists motivo_rechazo text not null default '' check (char_length(motivo_rechazo) <= 500);
alter table public.equipo_proyectos alter column revision set default 'pendiente';   -- los existentes quedan aceptados
alter table public.equipo_proyectos alter column abierto set default false;

-- Quien revisa: responsable de quien lidera el proyecto.
create or replace function public.es_revisor_de_proyecto(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.equipo_proyectos p join public.responsables r on r.persona_id = p.lider_id
    where p.id = p_id and r.responsable_id = auth.uid()
  );
$$;
revoke all on function public.es_revisor_de_proyecto(uuid) from public, anon;
grant execute on function public.es_revisor_de_proyecto(uuid) to authenticated;

-- "Participa": participante elegido (de su equipo), proyecto abierto a su equipo, o quien lo revisa.
-- Un proyecto rechazado deja de verse para participantes y equipo.
create or replace function public.es_miembro_de_proyecto(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.equipo_proyectos p
    where p.id = p_id
      and ((p.revision <> 'rechazado' and public.mismo_equipo(p.lider_id, auth.uid())
            and (p.abierto or exists (select 1 from public.equipo_proyecto_miembros m
                                      where m.proyecto_id = p.id and m.persona_id = auth.uid())))
           or exists (select 1 from public.responsables r where r.persona_id = p.lider_id and r.responsable_id = auth.uid()))
  );
$$;

-- Vincular tareas: responsable o participante, y solo si el proyecto no fue rechazado.
create or replace function public.puede_usar_proyecto(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select (public.es_lider_de_proyecto(p) or public.es_miembro_de_proyecto(p))
     and not exists (select 1 from public.equipo_proyectos x where x.id = p and x.revision = 'rechazado');
$$;

-- El responsable del proyecto suma participantes entre su equipo (no solo sus directos).
drop policy if exists "lider suma directos" on public.equipo_proyecto_miembros;
create policy "responsable suma participantes de su equipo" on public.equipo_proyecto_miembros for insert
  with check (public.es_lider_de_proyecto(proyecto_id) and public.mismo_equipo(auth.uid(), persona_id));

-- La revisión no se escribe desde la web (solo con las funciones de abajo).
create or replace function public.equipo_proyectos_proteger()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if tg_op = 'INSERT' then
    new.revisado_por := null; new.revisado_at := 0; new.motivo_rechazo := '';
    new.revision := case when exists (select 1 from public.responsables where persona_id = new.lider_id) then 'pendiente' else 'aceptado' end;
  else
    new.revision := old.revision; new.revisado_por := old.revisado_por;
    new.revisado_at := old.revisado_at; new.motivo_rechazo := old.motivo_rechazo;
  end if;
  return new;
end $$;
revoke execute on function public.equipo_proyectos_proteger() from public, anon, authenticated;
drop trigger if exists equipo_proyectos_proteger_t on public.equipo_proyectos;
create trigger equipo_proyectos_proteger_t before insert or update on public.equipo_proyectos
  for each row execute function public.equipo_proyectos_proteger();

-- Aviso al revisar: cuando alguien crea un proyecto, su responsable de equipo lo recibe.
create or replace function public.trg_aviso_proyecto_nuevo()
returns trigger language plpgsql security definer set search_path = public as $$
declare r uuid;
begin
  if new.revision <> 'pendiente' then return new; end if;
  for r in select responsable_id from public.responsables where persona_id = new.lider_id loop
    perform public.notificar(r, new.lider_id, 'proyectos', 'proyecto_para_revisar',
      public.nombre_de(new.lider_id) || ' creó un proyecto para revisar', new.nombre, 'proyecto', new.id);
  end loop;
  return new;
end $$;
revoke execute on function public.trg_aviso_proyecto_nuevo() from public, anon, authenticated;
drop trigger if exists trg_aviso_proyecto_nuevo_i on public.equipo_proyectos;
create trigger trg_aviso_proyecto_nuevo_i after insert on public.equipo_proyectos
  for each row execute function public.trg_aviso_proyecto_nuevo();

-- El responsable de equipo acepta o rechaza (puede cambiar su decisión).
create or replace function public.revisar_proyecto(p_id uuid, p_decision text, p_motivo text default '')
returns void language plpgsql security definer set search_path = public as $$
declare p public.equipo_proyectos%rowtype; v_now bigint := (extract(epoch from now()) * 1000)::bigint;
begin
  if p_decision not in ('aceptado', 'rechazado') then raise exception 'Decisión inválida.' using errcode = 'P0001'; end if;
  p_motivo := btrim(coalesce(p_motivo, ''));
  if p_decision = 'rechazado' and (char_length(p_motivo) = 0 or char_length(p_motivo) > 500) then
    raise exception 'Escribí el motivo del rechazo (hasta 500 caracteres).' using errcode = 'P0001';
  end if;
  select * into p from public.equipo_proyectos where id = p_id for update;
  if not found or not public.es_revisor_de_proyecto(p_id) then
    raise exception 'No podés revisar este proyecto.' using errcode = 'P0001';
  end if;
  update public.equipo_proyectos set revision = p_decision, revisado_por = auth.uid(), revisado_at = v_now,
    motivo_rechazo = case when p_decision = 'rechazado' then p_motivo else '' end where id = p_id;
  perform public.notificar(p.lider_id, auth.uid(), 'proyectos', 'proyecto_revisado',
    public.nombre_de(auth.uid()) || case when p_decision = 'aceptado' then ' aceptó tu proyecto' else ' rechazó tu proyecto' end,
    p.nombre || case when p_decision = 'rechazado' then ' — ' || p_motivo else '' end, 'proyecto', p_id);
end $$;
revoke all on function public.revisar_proyecto(uuid, text, text) from public, anon;
grant execute on function public.revisar_proyecto(uuid, text, text) to authenticated;

-- El responsable del proyecto pide una nueva revisión de uno rechazado.
create or replace function public.reenviar_proyecto(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare p public.equipo_proyectos%rowtype; r uuid;
begin
  select * into p from public.equipo_proyectos where id = p_id for update;
  if not found or p.lider_id is distinct from auth.uid() or p.revision <> 'rechazado' then
    raise exception 'No hay nada para reenviar.' using errcode = 'P0001';
  end if;
  update public.equipo_proyectos set revision = 'pendiente', revisado_por = null, revisado_at = 0, motivo_rechazo = '' where id = p_id;
  for r in select responsable_id from public.responsables where persona_id = p.lider_id loop
    perform public.notificar(r, p.lider_id, 'proyectos', 'proyecto_para_revisar',
      public.nombre_de(p.lider_id) || ' pidió revisar de nuevo un proyecto', p.nombre, 'proyecto', p_id);
  end loop;
end $$;
revoke all on function public.reenviar_proyecto(uuid) from public, anon;
grant execute on function public.reenviar_proyecto(uuid) to authenticated;
