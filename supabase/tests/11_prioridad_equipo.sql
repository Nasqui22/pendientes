do $$
declare l uuid := gen_random_uuid(); a uuid := gen_random_uuid(); o uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  tv uuid; tp uuid; tw uuid; tc uuid; n int; p text;
begin
  insert into auth.users (id,email,aud,role) values (l,'l@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(o,'o@t.local','authenticated','authenticated'),(x,'x@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (l,a,true);
  insert into tareas (user_id, text, prio, visible) values (a,'Visible','baja',true) returning id into tv;
  insert into tareas (user_id, text, prio, visible) values (a,'Privada','baja',false) returning id into tp;
  insert into tareas (user_id, text, prio, visible, status, validada_por, validada_at) values (a,'Validada','baja',true,'completado',l,1) returning id into tw;
  insert into tareas (user_id, text, prio, visible) values (o,'Ajena','baja',true) returning id into tc;
  -- el líder cambia la prioridad de una tarea visible de su directo
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform cambiar_prioridad_equipo(tv, 'alta');
  reset role;
  select prio into p from tareas where id = tv; if p <> 'alta' then raise exception 'FALLA: no cambió la prioridad'; end if;
  select count(*) into n from tareas where id = tv and jsonb_array_length(avances) = 1; if n <> 1 then raise exception 'FALLA: sin registro en avances'; end if;
  select count(*) into n from notificaciones where para_id = a and tipo = 'prioridad_cambiada'; if n <> 1 then raise exception 'FALLA: sin aviso'; end if;
  -- no sobre privadas, validadas, de otra persona ni con valor inválido
  set local role authenticated;
  begin perform cambiar_prioridad_equipo(tp, 'alta'); raise exception 'FALLA: cambió una privada'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform cambiar_prioridad_equipo(tw, 'alta'); raise exception 'FALLA: cambió una validada'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform cambiar_prioridad_equipo(tc, 'alta'); raise exception 'FALLA: cambió una de no-directo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform cambiar_prioridad_equipo(tv, 'urgente'); raise exception 'FALLA: valor inválido'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- un tercero sin relación y el propio dueño no pueden usarla
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated')::text, true);
  begin perform cambiar_prioridad_equipo(tv, 'baja'); raise exception 'FALLA: tercero cambió'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin perform cambiar_prioridad_equipo(tv, 'baja'); raise exception 'FALLA: el dueño usó la función de líder'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- anon no ejecuta
  reset role; set local role anon;
  begin perform cambiar_prioridad_equipo(tv, 'baja'); raise exception 'FALLA: anon ejecutó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
