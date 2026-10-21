do $$
declare l uuid := gen_random_uuid(); a uuid := gen_random_uuid(); o uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  tv uuid; tp uuid; tw uuid; tc uuid; td uuid; n int; r tareas%rowtype;
begin
  insert into auth.users (id,email,aud,role) values (l,'l@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(o,'o@t.local','authenticated','authenticated'),(x,'x@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (l,a,true),(l,o,true);
  insert into tareas (user_id, text, notes, visible, subs, avances) values (a,'Visible','',true,
    '[{"t":"uno","d":true},{"t":"dos","d":false}]', '[{"t":1,"x":"avance de la persona"}]') returning id into tv;
  insert into tareas (user_id, text, visible) values (a,'Privada',false) returning id into tp;
  insert into tareas (user_id, text, visible, status, validada_por, validada_at) values (a,'Validada',true,'completado',l,1) returning id into tw;
  insert into tareas (user_id, text, visible) values (x,'Ajena',true) returning id into tc;
  insert into tareas (user_id, text, visible, subs) values (a,'Con delegada',true,'[{"t":"pasada","d":false}]') returning id into td;
  insert into delegaciones (de_id, a_id, tarea_id, tarea_texto, texto) values (a,o,td,'Con delegada','pasada');

  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  set local role authenticated;
  -- edita título, descripción, fecha, etiquetas y subtareas (renombra, quita, agrega)
  perform editar_tarea_equipo(tv, 'Visible editada', 'nueva descripción', '2026-12-01', null, '["x"]'::jsonb,
    '[{"t":"uno renombrada","i":0},{"t":"tres","i":null}]'::jsonb);
  reset role;
  select * into r from tareas where id = tv;
  if r.text <> 'Visible editada' or r.notes <> 'nueva descripción' or r.due <> '2026-12-01' or r.labels <> '["x"]'::jsonb then raise exception 'FALLA: no editó los campos'; end if;
  if r.subs <> '[{"t":"uno renombrada","d":true},{"t":"tres","d":false}]'::jsonb then raise exception 'FALLA: subtareas %', r.subs; end if;
  if jsonb_array_length(r.avances) <> 2 or r.avances->0->>'x' <> 'avance de la persona' then raise exception 'FALLA: tocó los avances previos'; end if;
  if r.status <> 'pendiente' or not r.visible then raise exception 'FALLA: tocó estado o privacidad'; end if;
  select count(*) into n from notificaciones where para_id = a and tipo = 'tarea_editada'; if n <> 1 then raise exception 'FALLA: sin aviso'; end if;
  -- sin cambios no anota nada
  set local role authenticated;
  perform editar_tarea_equipo(tv, 'Visible editada');
  reset role;
  select count(*) into n from tareas where id = tv and jsonb_array_length(avances) = 2; if n <> 1 then raise exception 'FALLA: anotó sin cambios'; end if;
  -- la subtarea delegada no se quita ni se renombra
  set local role authenticated;
  begin perform editar_tarea_equipo(td, p_subs => '[]'::jsonb); raise exception 'FALLA: quitó una delegada'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform editar_tarea_equipo(td, p_subs => '[{"t":"otro nombre","i":0}]'::jsonb);
  reset role;
  select count(*) into n from tareas where id = td and subs->0->>'t' = 'pasada'; if n <> 1 then raise exception 'FALLA: renombró una delegada'; end if;
  -- no sobre privadas, validadas, de otra persona, título vacío ni fecha inválida
  set local role authenticated;
  begin perform editar_tarea_equipo(tp, 'x'); raise exception 'FALLA: editó una privada'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform editar_tarea_equipo(tw, 'x'); raise exception 'FALLA: editó una validada'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform editar_tarea_equipo(tc, 'x'); raise exception 'FALLA: editó una de no-directo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform editar_tarea_equipo(tv, '  '); raise exception 'FALLA: título vacío'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform editar_tarea_equipo(tv, p_due => 'mañana'); raise exception 'FALLA: fecha inválida'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform editar_tarea_equipo(tv, p_subs => '[{"t":"a","i":0},{"t":"b","i":0}]'::jsonb); raise exception 'FALLA: índice repetido'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- un compañero, un tercero y el propio dueño no pueden usarla
  perform set_config('request.jwt.claims', json_build_object('sub', o, 'role', 'authenticated')::text, true);
  begin perform editar_tarea_equipo(tv, 'x'); raise exception 'FALLA: compañero editó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated')::text, true);
  begin perform editar_tarea_equipo(tv, 'x'); raise exception 'FALLA: tercero editó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin perform editar_tarea_equipo(tv, 'x'); raise exception 'FALLA: el dueño usó la función de líder'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- anon no ejecuta
  reset role; set local role anon;
  begin perform editar_tarea_equipo(tv, 'x'); raise exception 'FALLA: anon ejecutó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
