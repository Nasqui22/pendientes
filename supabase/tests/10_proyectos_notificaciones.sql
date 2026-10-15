do $$
declare l uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); x uuid := gen_random_uuid();
        tid uuid; pid uuid; hid uuid; lib uuid; n int; k bigint; t record;
begin
  insert into auth.users (id,email,aud,role) values (l,'l@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated'),(c,'c@t.local','authenticated','authenticated'),(x,'x@t.local','authenticated','authenticated');
  update perfiles set nombre = 'Lider' where id = l; update perfiles set nombre = 'Ana' where id = a;
  -- responsable nuevo: avisa a la persona
  insert into responsables (responsable_id, persona_id, confirmado) values (l,a,true),(l,b,true),(l,c,false);
  select count(*) into n from notificaciones where para_id = c and tipo = 'responsable_nuevo'; if n <> 1 then raise exception 'FALLA: aviso de responsable nuevo (%)', n; end if;

  -- ===== tareas =====
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  set local role authenticated;
  tid := asignar_tarea(a, 'Armar informe');
  reset role;
  select count(*) into n from notificaciones where para_id = a and tipo = 'tarea_asignada' and ref_id = tid; if n <> 1 then raise exception 'FALLA: no avisó la asignación'; end if;
  select count(*) into n from notificaciones where para_id = l and tipo = 'tarea_asignada'; if n <> 0 then raise exception 'FALLA: avisó al que asignó'; end if;
  -- Ana completa la tarea asignada: avisa al responsable (no a ella)
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated; update tareas set status = 'completado', done_at = 1 where id = tid; reset role;
  select count(*) into n from notificaciones where para_id = l and tipo = 'tarea_completada' and ref_id = tid; if n <> 1 then raise exception 'FALLA: no avisó la tarea completada'; end if;
  select count(*) into n from notificaciones where para_id = a and tipo = 'tarea_completada'; if n <> 0 then raise exception 'FALLA: se avisó a sí misma'; end if;
  -- validar / devolver
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  set local role authenticated; perform validar_tarea(tid); reset role;
  select count(*) into n from notificaciones where para_id = a and tipo = 'tarea_validada'; if n <> 1 then raise exception 'FALLA: no avisó la validación'; end if;
  insert into tareas (user_id, text, visible, status) values (b, 'Otra', true, 'completado') returning id into tid;
  set local role authenticated; perform devolver_tarea(tid, 'Falta el adjunto'); reset role;
  select count(*) into n from notificaciones where para_id = b and tipo = 'tarea_devuelta' and cuerpo like '%Falta el adjunto%'; if n <> 1 then raise exception 'FALLA: no avisó la devolución'; end if;
  -- una tarea privada que se completa no avisa a nadie
  insert into tareas (user_id, text, visible) values (b, 'Privada', false) returning id into tid;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated; update tareas set status = 'completado' where id = tid; reset role;
  select count(*) into n from notificaciones where para_id = l and ref_id = tid; if n <> 0 then raise exception 'FALLA: avisó de una tarea privada'; end if;

  -- ===== comentarios: llegan a los demás, se agrupan y respetan preferencias =====
  insert into tareas (user_id, text, visible) values (a, 'Con hilo', true) returning id into tid;
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into comentarios (tarea_id, texto) values (tid, 'primero'); insert into comentarios (tarea_id, texto) values (tid, 'segundo');
  reset role;
  select count(*), max(cantidad) into n, k from notificaciones where para_id = a and tipo = 'comentario' and ref_id = tid and not leida; if n <> 1 or k <> 2 then raise exception 'FALLA: comentarios sin agrupar (n=%, cant=%)', n, k; end if;
  select count(*) into n from notificaciones where para_id = l and tipo = 'comentario'; if n <> 0 then raise exception 'FALLA: avisó al autor del comentario'; end if;
  insert into notif_prefs (persona_id, silenciadas) values (a, array['comentarios']);
  update notificaciones set leida = true where para_id = a and tipo = 'comentario';
  set local role authenticated; perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  insert into comentarios (tarea_id, texto) values (tid, 'tercero'); reset role;
  select count(*) into n from notificaciones where para_id = a and tipo = 'comentario' and not leida; if n <> 0 then raise exception 'FALLA: ignoró la preferencia de silencio'; end if;

  -- ===== permisos sobre las notificaciones =====
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from notificaciones where para_id <> a; if n <> 0 then raise exception 'FALLA: ve avisos ajenos'; end if;
  begin insert into notificaciones (para_id, grupo, tipo, titulo) values (a, 'tareas', 'x', 'falso'); raise exception 'FALLA: creó un aviso'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin update notificaciones set titulo = 'hack' where para_id = a; raise exception 'FALLA: editó el título'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  update notificaciones set leida = true where para_id = a;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  update notificaciones set leida = true where para_id = a; get diagnostics n = row_count; if n <> 0 then raise exception 'FALLA: marcó avisos ajenos'; end if;
  begin insert into notif_prefs (persona_id, silenciadas) values (b, array['inventado']); raise exception 'FALLA: preferencia inválida'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  delete from notificaciones where para_id = a; get diagnostics n = row_count; if n <> 0 then raise exception 'FALLA: borró avisos ajenos'; end if;
  reset role;

  -- ===== proyectos: fechas, hitos y avisos =====
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into equipo_proyectos (nombre, inicio, fin, estado) values ('Proy', '2026-10-01', '2026-12-31', 'activo') returning id into pid;
  begin insert into equipo_proyectos (nombre, fin) values ('malo', '31/12/2026'); raise exception 'FALLA: fecha inválida'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin update equipo_proyectos set estado = 'volando' where id = pid; raise exception 'FALLA: estado inválido'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  insert into equipo_proyecto_miembros values (pid, a), (pid, b);
  reset role;
  select count(*) into n from notificaciones where tipo = 'proyecto_asignado' and ref_id = pid; if n <> 2 then raise exception 'FALLA: avisos de proyecto (%)', n; end if;
  set local role authenticated;
  insert into proyecto_hitos (proyecto_id, titulo, fecha) values (pid, 'Entrega 1', '2026-11-15') returning id into hid;
  begin insert into proyecto_hitos (proyecto_id, titulo, fecha) values (pid, 'x', 'mañana'); raise exception 'FALLA: fecha de hito inválida'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  update proyecto_hitos set hecho = true where id = hid; reset role;
  select hecho_at into k from proyecto_hitos where id = hid; if k = 0 then raise exception 'FALLA: no registró hecho_at'; end if;
  select count(*) into n from notificaciones where tipo = 'hito_cumplido' and ref_id = pid; if n <> 2 then raise exception 'FALLA: avisos de hito (%)', n; end if;
  -- el miembro ve los hitos pero no los edita; el no miembro no ve nada
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from proyecto_hitos; if n <> 1 then raise exception 'FALLA: miembro no ve hitos'; end if;
  begin insert into proyecto_hitos (proyecto_id, titulo) values (pid, 'intruso'); raise exception 'FALLA: miembro creó hito'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  update proyecto_hitos set titulo = 'hack' where id = hid; get diagnostics n = row_count; if n <> 0 then raise exception 'FALLA: miembro editó hito'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from proyecto_hitos; if n <> 0 then raise exception 'FALLA: no miembro ve hitos'; end if;
  reset role;

  -- ===== libros: compartir, pedir lectura y actualizar avisan a la audiencia =====
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into libros (titulo, alcance, paginas) values ('Guía', 'equipo', '[{"t":"P","b":"uno"}]') returning id into lib; reset role;
  select count(*) into n from notificaciones where tipo = 'libro_compartido' and ref_id = lib; if n <> 3 then raise exception 'FALLA: avisos de libro compartido (%) esperaba 3 (L, B, C)', n; end if;
  select count(*) into n from notificaciones where ref_id = lib and para_id = x; if n <> 0 then raise exception 'FALLA: avisó a un ajeno'; end if;
  set local role authenticated; update libros set requiere_lectura = true where id = lib; reset role;
  select count(*) into n from notificaciones where tipo = 'lectura_pedida' and ref_id = lib; if n <> 3 then raise exception 'FALLA: avisos de lectura pedida (%)', n; end if;
  set local role authenticated; update libros set paginas = '[{"t":"P","b":"dos"}]' where id = lib; reset role;
  select count(*) into n from notificaciones where tipo = 'libro_actualizado' and ref_id = lib; if n <> 3 then raise exception 'FALLA: avisos de libro actualizado (%)', n; end if;
  -- un borrador no avisa
  set local role authenticated; insert into libros (titulo, alcance) values ('Borrador', 'privado') returning id into lib; reset role;
  select count(*) into n from notificaciones where ref_id = lib; if n <> 0 then raise exception 'FALLA: avisó de un borrador'; end if;
  raise exception 'TODO OK (rollback)';
end $$;
