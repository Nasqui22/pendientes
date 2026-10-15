-- Una subtarea ya aceptada por un compañero no se puede volver a pasar (duplicaría la tarea).
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
  if exists (select 1 from delegaciones where tarea_id = p_tarea and texto = p_texto and estado in ('pendiente', 'aceptada')) then
    raise exception 'Esa subtarea ya fue pasada y está pendiente o aceptada.';
  end if;
  insert into delegaciones (de_id, a_id, tarea_id, tarea_texto, texto)
  values (auth.uid(), p_a, p_tarea, t.text, left(p_texto, 200)) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.delegar_subtarea(uuid, text, uuid) from public, anon;
grant execute on function public.delegar_subtarea(uuid, text, uuid) to authenticated;
