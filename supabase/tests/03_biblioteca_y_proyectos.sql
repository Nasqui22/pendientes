do $$
declare l uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); x uuid := gen_random_uuid();
        lib uuid; lib2 uuid; pid uuid; n int;
begin
  insert into auth.users (id,email,aud,role) values (l,'l@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated'),(c,'c@t.local','authenticated','authenticated'),(x,'x@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id) values (l,a),(l,b),(l,c);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  -- A crea un libro privado y otro para el equipo
  insert into libros (titulo, paginas, enlaces) values ('Borrador', '[{"t":"Intro","b":"hola"}]', '[{"l":"Flujo","u":"https://ejemplo.com/x","k":"automatismo"}]') returning id into lib;
  insert into libros (titulo, alcance) values ('Para todos', 'equipo') returning id into lib2;
  begin insert into libros (titulo, enlaces) values ('mal', '[{"l":"x","u":"javascript:alert(1)","k":"ayuda"}]'); raise exception 'FALLA: aceptó javascript:'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into libros (titulo, alcance, destinatarios) values ('dirigido', 'personas', array[x]); raise exception 'FALLA: dirigió a ajeno'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- B (compañero) ve solo el de equipo; X (ajeno) nada
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from libros; if n <> 1 then raise exception 'FALLA: B ve % libros', n; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated')::text, true);
  select count(*) into n from libros; if n <> 0 then raise exception 'FALLA: ajeno ve libros'; end if;
  -- cualquiera crea sus proyectos (aunque no tenga gente a cargo), pero no a nombre de otro
  insert into equipo_proyectos (nombre) values ('p de ajeno');
  begin insert into equipo_proyectos (nombre, lider_id) values ('falso', l); raise exception 'FALLA: creó proyecto a nombre de otro'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  select count(*) into n from equipo_proyectos; if n <> 1 then raise exception 'FALLA: ajeno ve % proyectos', n; end if;
  -- B no puede editar libro de A
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  update libros set titulo = 'hack' where id = lib2; get diagnostics n = row_count; if n <> 0 then raise exception 'FALLA: B editó libro ajeno'; end if;
  -- El líder crea un proyecto, suma a B, y le asigna un libro propio (borrador de L)
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  insert into libros (titulo) values ('Guía del proyecto') returning id into lib;
  insert into equipo_proyectos (nombre, abierto) values ('Proyecto Uno', false) returning id into pid;
  insert into equipo_proyecto_miembros values (pid, b);
  begin insert into equipo_proyecto_miembros values (pid, x); raise exception 'FALLA: sumó a quien no es directo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  insert into equipo_proyecto_libros values (pid, lib);
  -- B ve el libro del proyecto y el proyecto; C (directo no miembro) no
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from libros where id = lib; if n <> 1 then raise exception 'FALLA: miembro no ve el libro del proyecto'; end if;
  select count(*) into n from equipo_proyectos; if n <> 1 then raise exception 'FALLA: miembro no ve el proyecto'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from libros where id = lib; if n <> 0 then raise exception 'FALLA: no miembro ve el libro'; end if;
  select count(*) into n from equipo_proyectos; if n <> 0 then raise exception 'FALLA: no miembro ve el proyecto'; end if;
  -- B no puede asignarse libros ni tocar proyectos
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  begin insert into equipo_proyecto_libros values (pid, lib); raise exception 'FALLA: miembro asignó libro'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
