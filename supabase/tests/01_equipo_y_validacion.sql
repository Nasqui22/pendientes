do $$
declare a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); tid uuid; n int; v_err text;
begin
  insert into auth.users (id, email, aud, role) values (a, 'ta@test.local', 'authenticated', 'authenticated'), (b, 'tb@test.local', 'authenticated', 'authenticated');
  insert into responsables (responsable_id, persona_id) values (a, b);  -- A responde por B, sin confirmar
  -- B crea tareas
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into tareas (user_id, text, visible, asignada_por, validada_por) values (b, 'privada', false, a, a);
  insert into tareas (user_id, text, visible) values (b, 'compartida', true) returning id into tid;
  select count(*) into n from tareas where asignada_por is not null or validada_por is not null;
  if n <> 0 then raise exception 'FALLA: el dueño pudo escribir asignada_por/validada_por'; end if;
  -- A (sin confirmar) no ve nada de B
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select count(*) into n from tareas where user_id = b;
  if n <> 0 then raise exception 'FALLA: A ve % tareas de B sin confirmación', n; end if;
  -- B confirma, A ve solo la compartida
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  perform confirmar_responsables();
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select count(*) into n from tareas where user_id = b;
  if n <> 1 then raise exception 'FALLA: A debería ver 1 tarea de B y ve %', n; end if;
  -- A asigna una tarea a B
  perform asignar_tarea(b, 'Asignada', 'alta', '2026-11-01', '');
  -- C (ajeno) no puede asignar
  begin perform asignar_tarea(a, 'x'); raise exception 'FALLA: asignó a quien no es directo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- B no puede borrar ni cambiar fecha de la asignada
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  delete from tareas where text = 'Asignada';
  select count(*) into n from tareas where text = 'Asignada';
  if n <> 1 then raise exception 'FALLA: B pudo borrar la asignada'; end if;
  update tareas set due = '2030-01-01', prio = 'baja' where text = 'Asignada';
  select count(*) into n from tareas where text = 'Asignada' and due = '2026-11-01' and prio = 'alta';
  if n <> 1 then raise exception 'FALLA: B cambió fecha/prioridad de la asignada'; end if;
  -- B completa la compartida; B no puede validarse a sí mismo
  update tareas set status = 'completado', done_at = 1 where id = tid;
  begin perform validar_tarea(tid); raise exception 'FALLA: B se validó solo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- A valida; luego B no puede reabrir
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform validar_tarea(tid);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  begin update tareas set status = 'proceso' where id = tid; raise exception 'FALLA: B reabrió una validada'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- A devuelve con motivo
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform devolver_tarea(tid, 'Falta el adjunto');
  select count(*) into n from tareas where id = tid and status = 'proceso' and validada_por is null and motivo_devolucion = 'Falta el adjunto';
  if n <> 1 then raise exception 'FALLA: devolver no dejó el estado esperado'; end if;
  -- anon no ejecuta funciones
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
