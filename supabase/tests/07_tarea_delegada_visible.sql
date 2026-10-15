do $$
declare r uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); x uuid := gen_random_uuid();
        tid uuid; did uuid; nt uuid; n int; v boolean;
begin
  insert into auth.users (id,email,aud,role) values (r,'r@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated'),(c,'c@t.local','authenticated','authenticated'),(x,'x@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (r,a,true),(r,b,true),(r,c,true);
  insert into tareas (user_id, text, subs) values (a, 'Informe', '[{"t":"Gráficos","d":false}]') returning id into tid;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  did := delegar_subtarea(tid, 'Gráficos', b);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  perform responder_delegacion(did, true);
  select id, visible into nt, v from tareas where user_id = b and text = 'Gráficos';
  if nt is null or not v then raise exception 'FALLA: la tarea aceptada no quedó visible'; end if;
  -- B intenta dejarla privada: debe seguir visible
  update tareas set visible = false where id = nt;
  select visible into v from tareas where id = nt; if not v then raise exception 'FALLA: B pudo dejarla privada'; end if;
  -- B no puede borrarla ni quitarle la marca de delegada
  delete from tareas where id = nt; select count(*) into n from tareas where id = nt; if n <> 1 then raise exception 'FALLA: B pudo borrarla'; end if;
  update tareas set delegada_por = null where id = nt;
  select count(*) into n from tareas where id = nt and delegada_por = a; if n <> 1 then raise exception 'FALLA: B pudo quitar delegada_por'; end if;
  -- B sigue pudiendo cambiar el estado y otras cosas
  update tareas set status = 'proceso' where id = nt; select count(*) into n from tareas where id = nt and status = 'proceso'; if n <> 1 then raise exception 'FALLA: B no puede avanzar su tarea'; end if;
  -- A (quien la pasó) ve esa tarea, y solo esa de B
  insert into tareas (user_id, text) values (b, 'otra privada de B');
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select count(*) into n from tareas where user_id = b; if n <> 1 then raise exception 'FALLA: A ve % tareas de B (debía ser 1)', n; end if;
  select count(*) into n from tareas where id = nt and status = 'proceso'; if n <> 1 then raise exception 'FALLA: A no ve el estado'; end if;
  -- A no puede editarla ni validarla
  update tareas set text = 'hack' where id = nt; select count(*) into n from tareas where id = nt and text = 'hack'; if n <> 0 then raise exception 'FALLA: A editó la tarea de B'; end if;
  begin perform validar_tarea(nt); raise exception 'FALLA: A validó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- C (compañero ajeno a la delegación) y X (ajeno al equipo) no ven nada de B
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from tareas where user_id = b; if n <> 0 then raise exception 'FALLA: compañero ve tareas de B'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated')::text, true);
  select count(*) into n from tareas where user_id = b; if n <> 0 then raise exception 'FALLA: ajeno ve tareas de B'; end if;
  -- R (responsable) ve la tarea delegada y la otra (visible por defecto)
  perform set_config('request.jwt.claims', json_build_object('sub', r, 'role', 'authenticated')::text, true);
  select count(*) into n from tareas where id = nt; if n <> 1 then raise exception 'FALLA: el responsable no ve la tarea delegada'; end if;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
