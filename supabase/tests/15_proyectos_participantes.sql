do $$
declare r uuid := gen_random_uuid(); l uuid := gen_random_uuid(); k uuid := gen_random_uuid(); o uuid := gen_random_uuid(); s uuid := gen_random_uuid();
  pid uuid; pid2 uuid; tk uuid; n int; st text;
begin
  insert into auth.users (id,email,aud,role) values (r,'r@t.local','authenticated','authenticated'),(l,'l@t.local','authenticated','authenticated'),(k,'k@t.local','authenticated','authenticated'),(o,'o@t.local','authenticated','authenticated'),(s,'s@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (r,l,true),(r,k,true);   -- R dirige a L y K (L y K son compañeros)
  -- L crea un proyecto: queda pendiente de revisión, cerrado a participantes y con aviso a R
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into equipo_proyectos (nombre, revision, revisado_por) values ('Plan de cambio', 'aceptado', l) returning id into pid;
  select revision into st from equipo_proyectos where id = pid; if st <> 'pendiente' then raise exception 'FALLA: la revisión se pudo falsear (%)', st; end if;
  select abierto::text into st from equipo_proyectos where id = pid; if st <> 'false' then raise exception 'FALLA: debía nacer cerrado a participantes'; end if;
  update equipo_proyectos set revision = 'aceptado' where id = pid;
  select revision into st from equipo_proyectos where id = pid; if st <> 'pendiente' then raise exception 'FALLA: el responsable se aceptó solo'; end if;
  reset role;
  select count(*) into n from notificaciones where para_id = r and tipo = 'proyecto_para_revisar'; if n <> 1 then raise exception 'FALLA: R sin aviso'; end if;
  -- K (compañero) no lo ve hasta que L lo sume; L suma a K pero no a un ajeno
  perform set_config('request.jwt.claims', json_build_object('sub', k, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from equipo_proyectos where id = pid; if n <> 0 then raise exception 'FALLA: K ve el proyecto sin ser participante'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  insert into equipo_proyecto_miembros values (pid, k);
  begin insert into equipo_proyecto_miembros values (pid, o); raise exception 'FALLA: sumó a alguien de fuera del equipo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform set_config('request.jwt.claims', json_build_object('sub', k, 'role', 'authenticated')::text, true);
  select count(*) into n from equipo_proyectos where id = pid; if n <> 1 then raise exception 'FALLA: K participante no ve el proyecto'; end if;
  insert into tareas (user_id, text, equipo_proyecto_id) values (k, 'Tarea nueva en el proyecto', pid) returning id into tk;
  begin insert into equipo_proyecto_miembros values (pid, k); exception when unique_violation then null; when others then null; end;
  begin insert into equipo_proyecto_miembros values (pid, s); raise exception 'FALLA: un participante sumó gente'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- ajeno no ve ni vincula
  perform set_config('request.jwt.claims', json_build_object('sub', o, 'role', 'authenticated')::text, true);
  select count(*) into n from equipo_proyectos where id = pid; if n <> 0 then raise exception 'FALLA: ajeno ve el proyecto'; end if;
  begin insert into tareas (user_id, text, equipo_proyecto_id) values (o, 'x', pid); raise exception 'FALLA: ajeno vinculó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- R lo ve sin ser participante; ni K ni L pueden revisar
  perform set_config('request.jwt.claims', json_build_object('sub', r, 'role', 'authenticated')::text, true);
  select count(*) into n from equipo_proyectos where id = pid; if n <> 1 then raise exception 'FALLA: el revisor no ve el proyecto'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', k, 'role', 'authenticated')::text, true);
  begin perform revisar_proyecto(pid, 'aceptado'); raise exception 'FALLA: un compañero revisó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  begin perform revisar_proyecto(pid, 'aceptado'); raise exception 'FALLA: el autor se revisó solo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- R rechaza (motivo obligatorio): K deja de verlo y no se vincula más; L sí lo ve
  perform set_config('request.jwt.claims', json_build_object('sub', r, 'role', 'authenticated')::text, true);
  begin perform revisar_proyecto(pid, 'rechazado', ''); raise exception 'FALLA: rechazó sin motivo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform revisar_proyecto(pid, 'rechazado', 'No es prioridad');
  perform set_config('request.jwt.claims', json_build_object('sub', k, 'role', 'authenticated')::text, true);
  select count(*) into n from equipo_proyectos where id = pid; if n <> 0 then raise exception 'FALLA: K ve un proyecto rechazado'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  select count(*) into n from equipo_proyectos where id = pid and motivo_rechazo = 'No es prioridad'; if n <> 1 then raise exception 'FALLA: L no ve el motivo'; end if;
  begin insert into tareas (user_id, text, equipo_proyecto_id) values (l, 'x', pid); raise exception 'FALLA: vinculó a un proyecto rechazado'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- L pide nueva revisión; R acepta; K lo vuelve a ver
  perform reenviar_proyecto(pid);
  select revision into st from equipo_proyectos where id = pid; if st <> 'pendiente' then raise exception 'FALLA: no se reenvió'; end if;
  begin perform reenviar_proyecto(pid); raise exception 'FALLA: reenvió uno no rechazado'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform set_config('request.jwt.claims', json_build_object('sub', r, 'role', 'authenticated')::text, true);
  perform revisar_proyecto(pid, 'aceptado');
  perform set_config('request.jwt.claims', json_build_object('sub', k, 'role', 'authenticated')::text, true);
  select count(*) into n from equipo_proyectos where id = pid; if n <> 1 then raise exception 'FALLA: K no lo ve aceptado'; end if;
  -- sin responsable de equipo no hay revisión pendiente
  perform set_config('request.jwt.claims', json_build_object('sub', r, 'role', 'authenticated')::text, true);
  insert into equipo_proyectos (nombre) values ('Mio') returning id into pid2;
  select revision into st from equipo_proyectos where id = pid2; if st <> 'aceptado' then raise exception 'FALLA: sin responsable debía quedar aceptado'; end if;
  reset role; set local role anon;
  begin perform revisar_proyecto(pid, 'aceptado'); raise exception 'FALLA: anon revisó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
