-- Centro de control del líder: editar las tareas de sus directos que ya puede ver
-- (asignadas por él o visibles y confirmadas), que no sean suyas ni estén validadas.
-- Edita título, descripción, fecha, prioridad, etiquetas y la lista de subtareas.
-- No toca lo que es de la persona: estado, avances, comentarios, privacidad, recurrencia,
-- archivo, proyecto ni el tildado de las subtareas. Las subtareas pasadas a un compañero
-- (delegación pendiente o aceptada) no se renombran ni se quitan.
-- Cada parámetro nulo significa "sin cambio". Queda anotado en Avances y avisa a la persona.
-- p_subs: arreglo [{t, i}] con i = posición de la subtarea original (o null si es nueva).
create or replace function public.editar_tarea_equipo(
  p_id uuid, p_text text default null, p_notes text default null, p_due text default null,
  p_prio text default null, p_labels jsonb default null, p_subs jsonb default null
) returns void language plpgsql security definer set search_path = public as $$
declare t tareas%rowtype; v_now bigint := (extract(epoch from now()) * 1000)::bigint;
  v_cambios text[] := '{}'; v_subs jsonb := '[]'::jsonb; e jsonb; o jsonb; v_i int; v_t text;
  v_deleg text[]; v_usadas int[] := '{}'; v_n int;
begin
  if auth.uid() is null then raise exception 'Sin sesión.'; end if;
  select * into t from tareas where id = p_id for update;
  if not found or t.user_id = auth.uid() or not ve_tarea_ajena(t.user_id, t.asignada_por, t.visible) then
    raise exception 'No podés editar esta tarea.';
  end if;
  if t.validada_por is not null then raise exception 'La tarea ya fue validada.'; end if;

  if p_text is not null then
    p_text := btrim(p_text);
    if p_text = '' then raise exception 'El título no puede quedar vacío.'; end if;
    if p_text is distinct from t.text then v_cambios := v_cambios || 'el título'::text; t.text := p_text; end if;
  end if;
  if p_notes is not null and p_notes is distinct from t.notes then
    v_cambios := v_cambios || 'la descripción'::text; t.notes := p_notes;
  end if;
  if p_due is not null and p_due is distinct from t.due then
    v_cambios := v_cambios || 'la fecha límite'::text; t.due := p_due;
  end if;
  if p_prio is not null and p_prio is distinct from t.prio then
    v_cambios := v_cambios || 'la prioridad'::text; t.prio := p_prio;
  end if;
  if p_labels is not null then
    if jsonb_typeof(p_labels) <> 'array' then raise exception 'Etiquetas inválidas.'; end if;
    if p_labels is distinct from t.labels then v_cambios := v_cambios || 'las etiquetas'::text; t.labels := p_labels; end if;
  end if;

  if p_subs is not null then
    if jsonb_typeof(p_subs) <> 'array' then raise exception 'Subtareas inválidas.'; end if;
    v_n := jsonb_array_length(t.subs);
    select coalesce(array_agg(texto), '{}') into v_deleg from delegaciones
      where tarea_id = p_id and estado in ('pendiente', 'aceptada');
    for e in select * from jsonb_array_elements(p_subs) loop
      if jsonb_typeof(e) <> 'object' or jsonb_typeof(e->'t') <> 'string' then raise exception 'Subtarea inválida.'; end if;
      v_t := btrim(e->>'t');
      if v_t = '' then continue; end if;
      if jsonb_typeof(e->'i') = 'number' then
        v_i := (e->>'i')::int;
        if v_i < 0 or v_i >= v_n or v_i = any(v_usadas) then raise exception 'Subtarea inválida.'; end if;
        v_usadas := v_usadas || v_i;
        o := t.subs -> v_i;
        -- conserva el tildado de la persona; una subtarea delegada mantiene su texto
        if (o->>'t') = any(v_deleg) then v_t := o->>'t'; end if;
        v_subs := v_subs || jsonb_build_array(jsonb_build_object('t', v_t, 'd', coalesce((o->>'d')::boolean, false)));
      else
        v_subs := v_subs || jsonb_build_array(jsonb_build_object('t', v_t, 'd', false));
      end if;
    end loop;
    for v_i in 0 .. v_n - 1 loop
      if not (v_i = any(v_usadas)) and (t.subs -> v_i ->> 't') = any(v_deleg) then
        raise exception 'No podés quitar una subtarea que se pasó a un compañero.';
      end if;
    end loop;
    if v_subs is distinct from (select coalesce(jsonb_agg(jsonb_build_object('t', x->>'t', 'd', coalesce((x->>'d')::boolean, false)) order by n), '[]'::jsonb)
                                from jsonb_array_elements(t.subs) with ordinality as s(x, n)) then
      v_cambios := v_cambios || 'las subtareas'::text; t.subs := v_subs;
    end if;
  end if;

  if array_length(v_cambios, 1) is null then return; end if;
  -- tareas_validar revisa largos, fecha, prioridad, etiquetas y subtareas
  update tareas set text = t.text, notes = t.notes, due = t.due, prio = t.prio, labels = t.labels, subs = t.subs,
    avances = avances || jsonb_build_array(jsonb_build_object('t', v_now,
      'x', nombre_de(auth.uid()) || ' editó ' || array_to_string(v_cambios, ', ')))
  where id = p_id;
  perform notificar(t.user_id, auth.uid(), 'tareas', 'tarea_editada', 'Editaron una tarea tuya',
    t.text || ' — ' || array_to_string(v_cambios, ', '), 'tarea', t.id);
end $$;
revoke all on function public.editar_tarea_equipo(uuid, text, text, text, text, jsonb, jsonb) from public, anon;
grant execute on function public.editar_tarea_equipo(uuid, text, text, text, text, jsonb, jsonb) to authenticated;
