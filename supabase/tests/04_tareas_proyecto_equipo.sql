do $$
declare l uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); pid uuid; pid2 uuid; tid uuid; n int;
begin
  insert into auth.users (id,email,aud,role) values (l,'l@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (l,a,true),(l,b,true);
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into equipo_proyectos (nombre, abierto) values ('P1', false) returning id into pid;
  insert into equipo_proyectos (nombre, abierto) values ('P2', false) returning id into pid2;
  insert into equipo_proyecto_miembros values (pid, a);
  -- asignar con proyecto: a miembro sí, a no miembro no
  perform asignar_tarea(a, 'Con proyecto', '', '', '', pid);
  begin perform asignar_tarea(b, 'x', '', '', '', pid); raise exception 'FALLA: asignó a no miembro'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- A vincula una tarea propia a P1 (miembro), no a P2 (no participa)
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  insert into tareas (user_id, text, equipo_proyecto_id) values (a, 'Mia', pid) returning id into tid;
  begin update tareas set equipo_proyecto_id = pid2 where id = tid; raise exception 'FALLA: vinculó a proyecto ajeno'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tareas (user_id, text, equipo_proyecto_id) values (a, 'x', pid2); raise exception 'FALLA: insertó con proyecto ajeno'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  update tareas set equipo_proyecto_id = null where id = tid;
  -- B (no miembro) no puede vincular a P1
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  begin insert into tareas (user_id, text, equipo_proyecto_id) values (b, 'x', pid); raise exception 'FALLA: no miembro vinculó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- la protección anterior sigue: dueño no puede escribir asignada_por
  insert into tareas (user_id, text, asignada_por) values (b, 'y', l);
  select count(*) into n from tareas where text = 'y' and asignada_por is not null; if n <> 0 then raise exception 'FALLA: protección de asignada_por rota'; end if;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
