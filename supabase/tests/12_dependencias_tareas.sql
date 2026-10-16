do $$
declare l uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  ta uuid; ta2 uuid; tp uuid; tb uuid; tx uuid; n int;
begin
  insert into auth.users (id,email,aud,role) values (l,'l@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated'),(x,'x@t.local','authenticated','authenticated');
  insert into responsables (responsable_id, persona_id, confirmado) values (l,a,true),(l,b,true);
  insert into tareas (user_id, text, visible) values (a,'A1',true) returning id into ta;
  insert into tareas (user_id, text, visible) values (a,'A2',true) returning id into ta2;
  insert into tareas (user_id, text, visible) values (a,'A privada',false) returning id into tp;
  insert into tareas (user_id, text, visible) values (b,'B1',true) returning id into tb;
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
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (ta, tb); raise exception 'FALLA: relacionó con tarea de un compañero'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (tx, ta); raise exception 'FALLA: relacionó con tarea ajena'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- no se puede falsear el autor
  begin insert into tarea_dependencias (tarea_id, bloqueada_por, creada_por) values (ta2, tp, l); raise exception 'FALLA: autor falso'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- B (compañero) no ve la relación; X tampoco
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from tarea_dependencias; if n <> 0 then raise exception 'FALLA: compañero ve la relación'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated')::text, true);
  select count(*) into n from tarea_dependencias; if n <> 0 then raise exception 'FALLA: ajeno ve la relación'; end if;
  delete from tarea_dependencias; get diagnostics n = row_count; if n <> 0 then raise exception 'FALLA: ajeno borró'; end if;
  -- el líder ve la relación (tareas visibles) y puede vincular tareas de dos directos
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated')::text, true);
  select count(*) into n from tarea_dependencias; if n <> 1 then raise exception 'FALLA: líder no ve la relación'; end if;
  insert into tarea_dependencias (tarea_id, bloqueada_por) values (tb, ta);
  -- pero no con una tarea privada de su directo
  begin insert into tarea_dependencias (tarea_id, bloqueada_por) values (tb, tp); raise exception 'FALLA: líder usó tarea privada'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- A ahora ve la relación con B? No: no ve la tarea de B
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  select count(*) into n from tarea_dependencias; if n <> 1 then raise exception 'FALLA: A ve una relación con tarea de B'; end if;
  -- el dueño puede quitar la suya
  delete from tarea_dependencias where tarea_id = ta; get diagnostics n = row_count; if n <> 1 then raise exception 'FALLA: no pudo quitar'; end if;
  -- anon no accede
  reset role; set local role anon;
  begin perform count(*) from tarea_dependencias; raise exception 'FALLA: anon lee'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
