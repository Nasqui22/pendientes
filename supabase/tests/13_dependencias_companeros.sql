do $$
declare l uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid();
  a1 uuid; a2 uuid; apriv uuid; b1 uuid; bpriv uuid; c1 uuid; did uuid; n int; st text;
begin
  insert into auth.users (id,email,aud,role) values (l,'l@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated'),(c,'c@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (l,a,true),(l,b,true);
  insert into tareas (user_id, text, visible) values (a,'A1',true) returning id into a1;
  insert into tareas (user_id, text, visible) values (a,'A2',true) returning id into a2;
  insert into tareas (user_id, text, visible) values (a,'A privada',false) returning id into apriv;
  insert into tareas (user_id, text, visible) values (b,'B1',true) returning id into b1;
  insert into tareas (user_id, text, visible) values (b,'B privada',false) returning id into bpriv;
  insert into tareas (user_id, text, visible) values (c,'C1',true) returning id into c1;

  -- A: mi tarea DEPENDE de una pública de B -> activa, sin aprobación
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from tareas_de_companeros() where user_id = b; if n <> 1 then raise exception 'FALLA: ve % tareas de B (esperaba 1, la pública)', n; end if;
  select count(*) into n from tareas_de_companeros() where user_id = c; if n <> 0 then raise exception 'FALLA: ve tareas de un ajeno'; end if;
  insert into tarea_dependencias (tarea_id, bloqueada_por) values (a1, b1);
  select estado into st from tarea_dependencias where tarea_id = a1; if st <> 'activa' then raise exception 'FALLA: depende de debía ser activa'; end if;
  -- no con privada de B ni con tarea de un ajeno
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (a2, bpriv); raise exception 'FALLA: dependió de una privada'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (a2, c1); raise exception 'FALLA: dependió de un ajeno'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- B recibe el aviso y, como A1 es pública, ve la relación
  reset role;
  select count(*) into n from notificaciones where para_id = b and tipo = 'dependencia_nueva'; if n <> 1 then raise exception 'FALLA: B sin aviso'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from tarea_dependencias; if n <> 1 then raise exception 'FALLA: B no ve la relación con tarea pública'; end if;
  -- C no ve nada
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from tarea_dependencias; if n <> 0 then raise exception 'FALLA: ajeno ve relaciones'; end if;
  -- si A1 pasa a privada, B deja de verla
  reset role; update tareas set visible = false where id = a1;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from tarea_dependencias; if n <> 0 then raise exception 'FALLA: B ve relación con tarea ya privada'; end if;
  reset role; update tareas set visible = true where id = a1;

  -- A: mi tarea BLOQUEA a una de B -> pendiente, aprobador B
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into tarea_dependencias (tarea_id, bloqueada_por) values (b1, a2) returning id into did;
  select estado into st from tarea_dependencias where id = did; if st <> 'pendiente' then raise exception 'FALLA: bloquea a debía quedar pendiente'; end if;
  -- no puede bloquear con una privada propia ni a una privada de B; no puede falsear estado
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (b1, apriv); raise exception 'FALLA: bloqueó con una privada propia'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (bpriv, a2); raise exception 'FALLA: bloqueó una privada de B'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (c1, a2); raise exception 'FALLA: bloqueó tarea de un ajeno'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- el solicitante no puede aprobar su propio pedido
  begin perform responder_dependencia(did, true); raise exception 'FALLA: se aprobó solo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- B ve el pedido y lo acepta
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from tarea_dependencias where id = did; if n <> 1 then raise exception 'FALLA: B no ve el pedido'; end if;
  perform responder_dependencia(did, true);
  select estado into st from tarea_dependencias where id = did; if st <> 'activa' then raise exception 'FALLA: no quedó activa'; end if;
  begin perform responder_dependencia(did, false); raise exception 'FALLA: respondió dos veces'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- rechazo: se borra
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into tarea_dependencias (tarea_id, bloqueada_por) values (b1, a1) returning id into did;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  perform responder_dependencia(did, false);
  select count(*) into n from tarea_dependencias where id = did; if n <> 0 then raise exception 'FALLA: el rechazo no borró'; end if;
  -- un tercero no puede responder pedidos ajenos
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  insert into tarea_dependencias (tarea_id, bloqueada_por) values (b1, a1) returning id into did;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  begin perform responder_dependencia(did, true); raise exception 'FALLA: tercero respondió'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- ciclo: B1 ya espera a A2 (aceptado); A2 no puede depender de B1
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (a2, b1); raise exception 'FALLA: círculo con compañero'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- dependencias_info no entrega tareas privadas ni ajenas
  select count(*) into n from dependencias_info(array[b1, bpriv, c1, apriv]); if n <> 2 then raise exception 'FALLA: dependencias_info devolvió % (esperaba b1 y apriv)', n; end if;
  reset role; set local role anon;
  begin perform * from tareas_de_companeros(); raise exception 'FALLA: anon ejecutó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
