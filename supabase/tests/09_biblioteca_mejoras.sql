do $$
declare l uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); x uuid := gen_random_uuid();
        lib uuid; n int; ver int; i int;
begin
  insert into auth.users (id,email,aud,role) values (l,'l@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated'),(c,'c@t.local','authenticated','authenticated'),(x,'x@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (l,a,true),(l,b,true),(l,c,true);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into libros (titulo, alcance, requiere_lectura, paginas) values ('Onboarding', 'equipo', true, '[{"t":"P1","b":"uno"}]') returning id into lib;
  select version into ver from libros where id = lib; if ver <> 1 then raise exception 'FALLA: versión inicial %', ver; end if;
  -- editar sin cambiar contenido (alcance) no sube la versión; cambiar contenido sí y guarda la anterior
  update libros set alcance = 'equipo', requiere_lectura = true where id = lib; select version into ver from libros where id = lib; if ver <> 1 then raise exception 'FALLA: subió versión sin cambio de contenido'; end if;
  update libros set paginas = '[{"t":"P1","b":"dos"}]' where id = lib; select version into ver from libros where id = lib; if ver <> 2 then raise exception 'FALLA: no subió la versión (%)', ver; end if;
  select count(*) into n from libro_versiones where libro_id = lib and version = 1 and paginas->0->>'b' = 'uno'; if n <> 1 then raise exception 'FALLA: no guardó la versión anterior'; end if;
  update libros set version = 99 where id = lib; select version into ver from libros where id = lib; if ver <> 2 then raise exception 'FALLA: forzó la versión'; end if;
  -- límite de 20 versiones
  for i in 1..25 loop update libros set paginas = jsonb_build_array(jsonb_build_object('t','P','b','v' || i)) where id = lib; end loop;
  select count(*) into n from libro_versiones where libro_id = lib; if n > 20 then raise exception 'FALLA: más de 20 versiones (%)', n; end if;
  -- el historial solo lo ve el autor; no se puede escribir
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from libro_versiones; if n <> 0 then raise exception 'FALLA: un lector ve el historial'; end if;
  begin insert into libro_versiones (libro_id, version, titulo) values (lib, 500, 'x'); raise exception 'FALLA: escribió versión'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- lectura: B confirma; el autor no; el ajeno no puede
  perform confirmar_lectura(lib);
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated')::text, true);
  begin perform confirmar_lectura(lib); raise exception 'FALLA: ajeno confirmó lectura'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin perform confirmar_lectura(lib); raise exception 'FALLA: el autor confirmó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  select count(*) into n from libro_lecturas where libro_id = lib; if n <> 1 then raise exception 'FALLA: el autor no ve las lecturas (n=%)', n; end if;
  -- C no ve la lectura de B
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from libro_lecturas; if n <> 0 then raise exception 'FALLA: otro lector ve lecturas ajenas'; end if;
  begin insert into libro_lecturas (libro_id, persona_id, version) values (lib, c, 1); raise exception 'FALLA: insertó lectura directa'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- audiencia: solo el autor la consulta; incluye a B y C (no a X ni al autor)
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select count(*) into n from libro_audiencia(lib); if n <> 3 then raise exception 'FALLA: audiencia = % (esperaba 3: L, B, C)', n; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from libro_audiencia(lib); if n <> 0 then raise exception 'FALLA: un lector consultó la audiencia'; end if;
  -- B actualiza su lectura tras una nueva versión
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  perform confirmar_lectura(lib); select version into ver from libro_lecturas where libro_id = lib and persona_id = b; select version into n from libros where id = lib; if ver <> n then raise exception 'FALLA: no actualizó la versión leída'; end if;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
