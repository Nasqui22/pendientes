do $$
declare n uuid := gen_random_uuid(); o uuid := gen_random_uuid(); l uuid := gen_random_uuid();
        tid uuid; lib uuid; pid uuid; pj uuid; did uuid;
        t record; cnt bigint; fails text := ''; ok int := 0;
        errs text[][]; zeros text[][];
begin
  insert into auth.users (id,email,aud,role) values (n,'n@t.local','authenticated','authenticated'),(o,'o@t.local','authenticated','authenticated'),(l,'l@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (l, o, true);   -- L es líder de O (no de N)
  insert into tareas (user_id, text, visible, status, done_at) values (o, 'tarea de O', true, 'completado', 1) returning id into tid;
  insert into libros (user_id, titulo) values (o, 'libro privado de O') returning id into lib;
  insert into equipo_proyectos (lider_id, nombre) values (l, 'proy de L') returning id into pid;
  insert into proyectos (user_id, nombre) values (o, 'personal de O') returning id into pj;
  insert into delegaciones (de_id, a_id, texto) values (o, l, 'x') returning id into did;
  update perfiles set es_admin = true where id = l;   -- L es admin (para probar que N no hereda nada)

  perform set_config('request.jwt.claims', json_build_object('sub', n, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- 1) lecturas: deben devolver 0 filas
  zeros := array[
   ['leer tareas de otro',            format('select count(*) from tareas where user_id = %L', o)],
   ['leer libro privado de otro',      format('select count(*) from libros where id = %L', lib)],
   ['leer proyecto personal de otro',  format('select count(*) from proyectos where id = %L', pj)],
   ['leer proyecto de equipo ajeno',   format('select count(*) from equipo_proyectos where id = %L', pid)],
   ['leer delegaciones ajenas',        format('select count(*) from delegaciones where id = %L', did)],
   ['leer perfil de otro',             format('select count(*) from perfiles where id in (%L,%L)', o, l)],
   ['leer responsables ajenos',        'select count(*) from responsables'],
   ['editar tarea de otro',            format('with x as (update tareas set text = ''hack'' where id = %L returning 1) select count(*) from x', tid)],
   ['borrar tarea de otro',            format('with x as (delete from tareas where id = %L returning 1) select count(*) from x', tid)],
   ['editar libro de otro',            format('with x as (update libros set titulo = ''hack'' where id = %L returning 1) select count(*) from x', lib)],
   ['borrar libro de otro',            format('with x as (delete from libros where id = %L returning 1) select count(*) from x', lib)],
   ['hacerse admin (update perfiles)', format('with x as (update perfiles set es_admin = true where id = %L returning 1) select count(*) from x', n)],
   ['cambiar su propio activo',        format('with x as (update perfiles set activo = true where id = %L returning 1) select count(*) from x', n)],
   ['tocar responsables (confirmado)', 'with x as (update responsables set confirmado = true returning 1) select count(*) from x'],
   ['borrar responsables',             'with x as (delete from responsables returning 1) select count(*) from x'],
   ['editar proyecto personal ajeno',  format('with x as (update proyectos set nombre = ''x'' where id = %L returning 1) select count(*) from x', pj)],
   ['editar proyecto de equipo ajeno', format('with x as (update equipo_proyectos set nombre = ''x'' where id = %L returning 1) select count(*) from x', pid)],
   ['editar delegacion ajena',         format('with x as (update delegaciones set estado = ''aceptada'' where id = %L returning 1) select count(*) from x', did)]
  ];
  for i in 1..array_length(zeros,1) loop
    begin
      execute zeros[i][2] into cnt;
      if cnt <> 0 then fails := fails || E'\n  - ' || zeros[i][1] || ' (devolvió/afectó ' || cnt || ')'; else ok := ok + 1; end if;
    exception when others then ok := ok + 1;  -- un error también es un rechazo
    end;
  end loop;

  -- 2) escrituras/acciones: deben fallar con error
  errs := array[
   ['crear tarea a nombre de otro',     format('insert into tareas (user_id, text) values (%L, ''x'')', o)],
   ['crear libro a nombre de otro',     format('insert into libros (user_id, titulo) values (%L, ''x'')', o)],
   ['insertar perfil',                  format('insert into perfiles (id, email) values (%L, ''x'')', gen_random_uuid())],
   ['asignarse como responsable',       format('insert into responsables (responsable_id, persona_id) values (%L, %L)', n, o)],
   ['crear proyecto de equipo (no líder)', 'insert into equipo_proyectos (nombre) values (''x'')'],
   ['crear delegación directa',         format('insert into delegaciones (de_id, a_id, texto) values (%L, %L, ''x'')', n, o)],
   ['asignar tarea a quien no es directo', format('select asignar_tarea(%L, ''x'')', o)],
   ['validar tarea ajena',              format('select validar_tarea(%L)', tid)],
   ['devolver tarea ajena',             format('select devolver_tarea(%L, ''x'')', tid)],
   ['retirar tarea ajena',              format('select retirar_tarea(%L)', tid)],
   ['delegar a alguien fuera del equipo', format('select delegar_subtarea(%L, ''x'', %L)', tid, o)],
   ['responder delegación ajena',       format('select responder_delegacion(%L, true)', did)],
   ['cancelar delegación ajena',        format('select cancelar_delegacion(%L)', did)],
   ['vincular a proyecto de equipo ajeno', format('insert into tareas (user_id, text, equipo_proyecto_id) values (%L, ''x'', %L)', n, pid)],
   ['libro dirigido a ajeno',           format('insert into libros (titulo, alcance, destinatarios) values (''x'', ''personas'', array[%L::uuid])', o)],
   ['enlace javascript: en libro',      'insert into libros (titulo, enlaces) values (''x'', ''[{"l":"a","u":"javascript:alert(1)","k":"ayuda"}]'')']
  ];
  for i in 1..array_length(errs,1) loop
    begin
      execute errs[i][2];
      fails := fails || E'\n  - ' || errs[i][1] || ' (se permitió)';
    exception when others then ok := ok + 1;
    end;
  end loop;

  -- 3) es_admin() debe ser falso, y los campos protegidos no se pueden forzar
  if es_admin() then fails := fails || E'\n  - es_admin() verdadero para un usuario común'; else ok := ok + 1; end if;
  insert into tareas (user_id, text, asignada_por, validada_por, validada_at, visible) values (n, 'mía', l, l, 99, true);
  select * into t from tareas where text = 'mía';
  if t.asignada_por is not null or t.validada_por is not null or t.validada_at <> 0 then fails := fails || E'\n  - pudo forzar asignada_por/validada_*'; else ok := ok + 1; end if;

  -- 4) anónimo (sin sesión)
  reset role; set local role anon;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin select count(*) into cnt from tareas; if cnt <> 0 then fails := fails || E'\n  - anon lee tareas'; else ok := ok + 1; end if; exception when others then ok := ok + 1; end;
  begin select count(*) into cnt from perfiles; if cnt <> 0 then fails := fails || E'\n  - anon lee perfiles'; else ok := ok + 1; end if; exception when others then ok := ok + 1; end;
  begin select count(*) into cnt from libros; if cnt <> 0 then fails := fails || E'\n  - anon lee libros'; else ok := ok + 1; end if; exception when others then ok := ok + 1; end;
  begin perform validar_tarea(tid); fails := fails || E'\n  - anon ejecuta validar_tarea'; exception when others then ok := ok + 1; end;
  begin perform asignar_tarea(o, 'x'); fails := fails || E'\n  - anon ejecuta asignar_tarea'; exception when others then ok := ok + 1; end;

  reset role;
  if fails = '' then raise exception 'RESULTADO: % comprobaciones OK, 0 fallas (rollback)', ok;
  else raise exception 'RESULTADO: % OK. FALLAS:%', ok, fails; end if;
end $$;
