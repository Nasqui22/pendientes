do $$
declare n uuid := gen_random_uuid(); o uuid := gen_random_uuid(); ad uuid := gen_random_uuid(); i int; tid uuid;
begin
  insert into auth.users (id,email,aud,role) values (n,'n@t.local','authenticated','authenticated'),(o,'o@t.local','authenticated','authenticated'),(ad,'ad@t.local','authenticated','authenticated');
  update perfiles set es_admin = true where id = ad;
  perform set_config('request.jwt.claims', json_build_object('sub', ad, 'role', 'authenticated')::text, true);
  set local role authenticated;
  -- el admin no puede crear responsable ya confirmado, sí uno sin confirmar
  begin insert into responsables (responsable_id, persona_id, confirmado) values (ad, o, true); raise exception 'FALLA: admin confirmó por la persona'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  insert into responsables (responsable_id, persona_id) values (ad, o);
  perform set_config('request.jwt.claims', json_build_object('sub', n, 'role', 'authenticated')::text, true);
  -- validación del servidor
  begin insert into tareas (user_id, text) values (n, repeat('x', 301)); raise exception 'FALLA: título largo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tareas (user_id, text, due) values (n, 'a', '<script>'); raise exception 'FALLA: fecha basura'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tareas (user_id, text, prio) values (n, 'a', 'urgentisima'); raise exception 'FALLA: prioridad'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tareas (user_id, text, labels) values (n, 'a', '[1,2]'); raise exception 'FALLA: etiquetas no texto'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tareas (user_id, text, subs) values (n, 'a', '["x"]'); raise exception 'FALLA: subs no objeto'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  insert into tareas (user_id, text, notes, due, prio, labels, subs, avances) values (n, 'ok', 'n', '2026-12-31', 'alta', '["a"]', '[{"t":"s","d":false}]', '[{"t":1,"x":"av"}]') returning id into tid;
  -- límite de libros y de proyectos personales
  for i in 1..100 loop insert into proyectos (nombre) values ('p' || i); end loop;
  begin insert into proyectos (nombre) values ('uno mas'); raise exception 'FALLA: sin límite de proyectos'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- usuario común sin acceso a la tabla de auditoría ni a funciones internas
  begin perform 1 from admin_acciones; raise exception 'FALLA: leyó admin_acciones'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform public.tareas_validar(); raise exception 'FALLA: ejecutó función interna'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin execute 'truncate table public.tareas'; raise exception 'FALLA: TRUNCATE permitido'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
