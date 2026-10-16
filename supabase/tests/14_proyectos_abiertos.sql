do $$
declare l uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid();
  pid uuid; ta uuid; lib uuid; n int;
begin
  insert into auth.users (id,email,aud,role) values (l,'l@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated'),(c,'c@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (l,a,true),(l,b,true);
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into equipo_proyectos (nombre) values ('Plan de cambio') returning id into pid;
  insert into equipo_proyecto_miembros values (pid, b);              -- A no es miembro
  insert into proyecto_hitos (proyecto_id, titulo) values (pid, 'Hito 1');
  insert into libros (titulo) values ('Guia') returning id into lib;
  insert into equipo_proyecto_libros values (pid, lib);
  reset role;
  -- A (directo del líder, no miembro) ve el proyecto abierto, sus hitos, miembros y libros
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from equipo_proyectos where id = pid; if n <> 1 then raise exception 'FALLA: A no ve el proyecto abierto'; end if;
  select count(*) into n from proyecto_hitos where proyecto_id = pid; if n <> 1 then raise exception 'FALLA: A no ve los hitos'; end if;
  select count(*) into n from equipo_proyecto_miembros where proyecto_id = pid; if n <> 1 then raise exception 'FALLA: A no ve los miembros'; end if;
  select count(*) into n from libros where id = lib; if n <> 1 then raise exception 'FALLA: A no ve el libro del proyecto'; end if;
  -- puede vincular su propia tarea
  insert into tareas (user_id, text, equipo_proyecto_id) values (a, 'Mia', pid) returning id into ta;
  -- pero no editar nada del proyecto
  update equipo_proyectos set nombre = 'Hackeado' where id = pid; get diagnostics n = row_count; if n <> 0 then raise exception 'FALLA: A editó el proyecto'; end if;
  begin insert into proyecto_hitos (proyecto_id, titulo) values (pid, 'x'); raise exception 'FALLA: A creó hito'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into equipo_proyecto_miembros values (pid, a); raise exception 'FALLA: A se sumó como miembro'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  delete from equipo_proyectos where id = pid; get diagnostics n = row_count; if n <> 0 then raise exception 'FALLA: A borró el proyecto'; end if;
  -- C (sin relación con el equipo) no ve nada ni puede vincular
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from equipo_proyectos; if n <> 0 then raise exception 'FALLA: ajeno ve el proyecto'; end if;
  select count(*) into n from libros where id = lib; if n <> 0 then raise exception 'FALLA: ajeno ve el libro'; end if;
  begin insert into tareas (user_id, text, equipo_proyecto_id) values (c, 'x', pid); raise exception 'FALLA: ajeno vinculó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- el líder lo cierra: A deja de verlo (B, miembro, sigue viéndolo)
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  update equipo_proyectos set abierto = false where id = pid;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select count(*) into n from equipo_proyectos where id = pid; if n <> 0 then raise exception 'FALLA: A ve el proyecto cerrado'; end if;
  begin update tareas set equipo_proyecto_id = pid, text = 'otra' where id = ta and false; end;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from equipo_proyectos where id = pid; if n <> 1 then raise exception 'FALLA: el miembro perdió el proyecto'; end if;
  reset role; set local role anon;
  begin perform count(*) from equipo_proyectos; raise exception 'FALLA: anon lee'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
