do $$
declare r uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid();
        tid uuid; did uuid; n int;
begin
  insert into auth.users (id, email, aud, role) values (r,'r@test.local','authenticated','authenticated'),(a,'a@test.local','authenticated','authenticated'),(b,'b@test.local','authenticated','authenticated'),(c,'c@test.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id) values (r,a),(r,b);  -- a y b son compañeros; c es ajeno
  insert into tareas (user_id, text, subs) values (a, 'Informe', '[{"t":"Armar gráficos","d":false}]') returning id into tid;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from mis_companeros(); if n <> 1 then raise exception 'FALLA: compañeros=%', n; end if;
  begin perform delegar_subtarea(tid, 'Armar gráficos', c); raise exception 'FALLA: delegó a ajeno'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  did := delegar_subtarea(tid, 'Armar gráficos', b);
  begin perform delegar_subtarea(tid, 'Armar gráficos', b); raise exception 'FALLA: duplicó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- b ve la solicitud y el nombre de a; c no ve nada; a no puede responder por b
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from delegaciones; if n <> 1 then raise exception 'FALLA: b ve %', n; end if;
  select count(*) into n from perfiles where id = a; if n <> 1 then raise exception 'FALLA: b no ve el perfil de su compañero'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from delegaciones; if n <> 0 then raise exception 'FALLA: ajeno ve delegaciones'; end if;
  select count(*) into n from perfiles where id in (a,b); if n <> 0 then raise exception 'FALLA: ajeno ve perfiles'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin perform responder_delegacion(did, true); raise exception 'FALLA: a aceptó su propia solicitud'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into delegaciones (de_id, a_id, texto) values (a, b, 'x'); raise exception 'FALLA: insertó directo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- b acepta -> se crea tarea para b
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  perform responder_delegacion(did, true);
  select count(*) into n from tareas where user_id = b and text = 'Armar gráficos'; if n <> 1 then raise exception 'FALLA: no se creó la tarea'; end if;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
