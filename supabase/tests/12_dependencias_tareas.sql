do $$
declare l uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  ta uuid; ta2 uuid; tp uuid; tb uuid; tbp uuid; tx uuid; n int;
begin
  insert into auth.users (id,email,aud,role) values (l,'l@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated'),(x,'x@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (l,a,true),(l,b,true);
  insert into tareas (user_id, text, visible) values (a,'A1',true) returning id into ta;
  insert into tareas (user_id, text, visible) values (a,'A2',true) returning id into ta2;
  insert into tareas (user_id, text, visible) values (a,'A privada',false) returning id into tp;
  insert into tareas (user_id, text, visible) values (b,'B1',true) returning id into tb;
  insert into tareas (user_id, text, visible) values (b,'B privada',false) returning id into tbp;
  insert into tareas (user_id, text, visible) values (x,'X1',true) returning id into tx;
  -- A relaciona dos tareas propias (aunque sean de proyectos distintos)
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into tarea_dependencias (tarea_id, bloqueada_por) values (ta, ta2);
  -- no consigo mismo, no duplicada, no en círculo
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (ta, ta); raise exception 'FALLA: consigo misma'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (ta, ta2); raise exception 'FALLA: duplicada'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (ta2, ta); raise exception 'FALLA: círculo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- A no puede relacionar con tareas que no ve (de B ni de X)
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (ta, tbp); raise exception 'FALLA: relacionó con tarea privada de un compañero'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (tx, ta); raise exception 'FALLA: relacionó con tarea ajena'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- no se puede falsear el autor
  insert into tarea_dependencias (tarea_id, bloqueada_por, creada_por) values (ta2, tp, l);
  select count(*) into n from tarea_dependencias where tarea_id = ta2 and bloqueada_por = tp and creada_por = a; if n <> 1 then raise exception 'FALLA: autor falso'; end if;
  delete from tarea_dependencias where tarea_id = ta2 and bloqueada_por = tp;
  -- B (compañero) no ve la relación; X tampoco
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  -- las dos tareas son públicas: un compañero puede ver la relación (ver 13 para las privadas)
  select count(*) into n from tarea_dependencias; if n <> 1 then raise exception 'FALLA: compañero no ve relación entre tareas públicas'; end if;
  delete from tarea_dependencias; get diagnostics n = row_count; if n <> 0 then raise exception 'FALLA: compañero borró relación ajena'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated')::text, true);
  select count(*) into n from tarea_dependencias; if n <> 0 then raise exception 'FALLA: ajeno ve la relación'; end if;
  delete from tarea_dependencias; get diagnostics n = row_count; if n <> 0 then raise exception 'FALLA: ajeno borró'; end if;
  -- el líder ve la relación (tareas visibles) y puede vincular tareas de dos directos
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  select count(*) into n from tarea_dependencias; if n <> 1 then raise exception 'FALLA: líder no ve la relación'; end if;
  insert into tarea_dependencias (tarea_id, bloqueada_por) values (tb, ta);
  -- pero no con una tarea privada de su directo
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (tb, tp); raise exception 'FALLA: líder usó tarea privada'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- A ve la relación con la tarea pública de B
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select count(*) into n from tarea_dependencias; if n <> 2 then raise exception 'FALLA: A debía ver 2 relaciones (la suya y la de la tarea pública de B), vio %', n; end if;
  -- el dueño puede quitar la suya
  delete from tarea_dependencias where tarea_id = ta; get diagnostics n = row_count; if n <> 1 then raise exception 'FALLA: no pudo quitar'; end if;
  -- anon no accede
  reset role; set local role anon;
  begin perform count(*) from tarea_dependencias; raise exception 'FALLA: anon lee'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
