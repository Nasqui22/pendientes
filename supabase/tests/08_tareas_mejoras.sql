do $$
declare r uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); x uuid := gen_random_uuid();
        tid uuid; nt uuid; did uuid; cid uuid; n int; v boolean; rec record; sub jsonb;
begin
  insert into auth.users (id,email,aud,role) values (r,'r@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated'),(x,'x@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (r,a,true),(r,b,true);
  -- ===== comentarios =====
  insert into tareas (user_id, text, visible) values (a, 'compartida', true) returning id into tid;
  insert into tareas (user_id, text, visible) values (a, 'privada', false);
  perform set_config('request.jwt.claims', json_build_object('sub', r, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into comentarios (tarea_id, texto) values (tid, 'Hola, ¿cómo va?');                 -- el responsable comenta
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select count(*) into n from comentarios where tarea_id = tid; if n <> 1 then raise exception 'FALLA: dueño no ve el comentario'; end if;
  insert into comentarios (tarea_id, texto) values (tid, 'Bien, termino hoy');
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated')::text, true);
  select count(*) into n from comentarios; if n <> 0 then raise exception 'FALLA: ajeno ve comentarios'; end if;
  begin insert into comentarios (tarea_id, texto) values (tid, 'intruso'); raise exception 'FALLA: ajeno comentó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);   -- compañero sin acceso
  select count(*) into n from comentarios; if n <> 0 then raise exception 'FALLA: compañero ve comentarios'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin insert into comentarios (tarea_id, texto, autor_id) values (tid, 'suplantación', r); raise exception 'FALLA: suplantó autor'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  update tareas set visible = false where id = tid;                                      -- al hacerla privada, el responsable pierde el hilo
  perform set_config('request.jwt.claims', json_build_object('sub', r, 'role', 'authenticated')::text, true);
  select count(*) into n from comentarios where tarea_id = tid; if n <> 0 then raise exception 'FALLA: responsable ve el hilo de una tarea privada'; end if;
  reset role;
  -- ===== subtarea que se tilda sola =====
  insert into tareas (user_id, text, subs) values (a, 'Informe', '[{"t":"Gráficos","d":false},{"t":"Otro","d":false}]') returning id into tid;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  did := delegar_subtarea(tid, 'Gráficos', b);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  perform responder_delegacion(did, true);
  select id into nt from tareas where user_id = b and text = 'Gráficos';
  update tareas set status = 'completado', done_at = 5 where id = nt;
  reset role; select subs into sub from tareas where id = tid;
  if not ((sub->0->>'d')::boolean) or (sub->1->>'d')::boolean then raise exception 'FALLA: la subtarea no se tildó sola (%)', sub; end if;
  set local role authenticated; perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  update tareas set status = 'proceso', done_at = 0 where id = nt;
  reset role; select subs into sub from tareas where id = tid;
  if (sub->0->>'d')::boolean then raise exception 'FALLA: la subtarea no se destildó al reabrir'; end if;
  -- ===== recurrencia =====
  set local role authenticated; perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  insert into tareas (user_id, text, due, recurrencia, subs, prio) values (a, 'Reporte semanal', to_char(current_date, 'YYYY-MM-DD'), 'semanal', '[{"t":"s1","d":true}]', 'alta') returning id into tid;
  update tareas set status = 'completado', done_at = 7 where id = tid;
  select count(*) into n from tareas where user_id = a and text = 'Reporte semanal' and status = 'pendiente'; if n <> 1 then raise exception 'FALLA: no creó la siguiente (n=%)', n; end if;
  select * into rec from tareas where user_id = a and text = 'Reporte semanal' and status = 'pendiente';
  if rec.due <> to_char(current_date + 7, 'YYYY-MM-DD') then raise exception 'FALLA: fecha siguiente = %', rec.due; end if;
  if (rec.subs->0->>'d')::boolean or rec.prio <> 'alta' or rec.recurrencia <> 'semanal' then raise exception 'FALLA: copia incorrecta'; end if;
  update tareas set status = 'proceso' where id = tid; update tareas set status = 'completado' where id = tid;    -- reabrir y completar de nuevo no duplica
  select count(*) into n from tareas where user_id = a and text = 'Reporte semanal'; if n <> 2 then raise exception 'FALLA: duplicó (n=%)', n; end if;
  begin update tareas set siguiente_id = tid where id = tid; select siguiente_id into cid from tareas where id = tid; if cid = tid then raise exception 'FALLA: forzó siguiente_id'; end if; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin update tareas set recurrencia = 'cada_minuto' where id = tid; raise exception 'FALLA: recurrencia inválida'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- ===== archivo =====
  insert into tareas (user_id, text, status, done_at) values (a, 'vieja', 'completado', 1) returning id into tid;
  update tareas set archivada = true where id = tid; select archivada into v from tareas where id = tid; if not v then raise exception 'FALLA: no archivó'; end if;
  update tareas set status = 'pendiente' where id = tid; select archivada into v from tareas where id = tid; if v then raise exception 'FALLA: sigue archivada al reabrir'; end if;
  insert into tareas (user_id, text, archivada) values (a, 'abierta', true); select archivada into v from tareas where text = 'abierta' and user_id = a; if v then raise exception 'FALLA: archivó una abierta'; end if;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
