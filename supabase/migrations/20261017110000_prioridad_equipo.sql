-- Centro de control del líder: cambiar la prioridad de las tareas de sus directos.
-- Solo sobre tareas que el líder ya puede ver (asignadas por él o visibles y confirmadas),
-- que no sean suyas ni estén validadas. Queda anotado en Avances y avisa a la persona.
create or replace function public.cambiar_prioridad_equipo(p_id uuid, p_prio text)
returns void language plpgsql security definer set search_path = public as $$
declare t tareas%rowtype; v_now bigint := (extract(epoch from now()) * 1000)::bigint; v_txt text;
begin
  if auth.uid() is null then raise exception 'Sin sesión.'; end if;
  if coalesce(p_prio, '') not in ('', 'alta', 'media', 'baja') then raise exception 'Prioridad inválida.'; end if;
  select * into t from tareas where id = p_id for update;
  if not found or t.user_id = auth.uid() or not ve_tarea_ajena(t.user_id, t.asignada_por, t.visible) then
    raise exception 'No podés cambiar la prioridad de esta tarea.';
  end if;
  if t.validada_por is not null then raise exception 'La tarea ya fue validada.'; end if;
  if t.prio is not distinct from coalesce(p_prio, '') then return; end if;
  v_txt := case coalesce(p_prio, '') when 'alta' then 'alta' when 'media' then 'media' when 'baja' then 'baja' else 'sin prioridad' end;
  update tareas set prio = coalesce(p_prio, ''),
    avances = avances || jsonb_build_array(jsonb_build_object('t', v_now, 'x', nombre_de(auth.uid()) || ' cambió la prioridad a ' || v_txt))
  where id = p_id;
  perform notificar(t.user_id, auth.uid(), 'tareas', 'prioridad_cambiada', 'Cambió la prioridad de una tarea', t.text || ' — ' || v_txt, 'tarea', t.id);
end $$;
revoke all on function public.cambiar_prioridad_equipo(uuid, text) from public, anon;
grant execute on function public.cambiar_prioridad_equipo(uuid, text) to authenticated;
