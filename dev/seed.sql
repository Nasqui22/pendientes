-- Datos de PRUEBA para la base local (clave de todos: DevPendientes1). Nunca se aplica a producción.
do $$
declare
  ms bigint := (extract(epoch from now()) * 1000)::bigint;
  day bigint := 86400000;
  u record; i int; st text; cr bigint; dn bigint; due text; pid uuid;
  ids uuid[] := array[
    '00000000-0000-0000-0000-00000000a001','00000000-0000-0000-0000-00000000a002','00000000-0000-0000-0000-00000000a003',
    '00000000-0000-0000-0000-00000000a004','00000000-0000-0000-0000-00000000a005'];
  nombres text[] := array['Administrador','Virginia Líder','Ana Pérez','Beto Gómez','Carla Díaz'];
  mails text[] := array['admin@dev.local','virginia@dev.local','ana@dev.local','beto@dev.local','carla@dev.local'];
begin
  for i in 1..5 loop
    insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,reauthentication_token,phone_change,phone_change_token)
    values ('00000000-0000-0000-0000-000000000000', ids[i],'authenticated','authenticated', mails[i], crypt('DevPendientes1', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', jsonb_build_object('nombre', nombres[i]), now(), now(),'','','','','','','','')
    on conflict (id) do nothing;
    insert into auth.identities (provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
    values (ids[i]::text, ids[i], jsonb_build_object('sub', ids[i]::text,'email', mails[i]), 'email', now(), now(), now()) on conflict do nothing;
  end loop;
  -- idempotente: se puede correr de nuevo sin duplicar
  delete from public.tareas where user_id = any(ids);
  delete from public.libros where user_id = any(ids);
  update public.perfiles set es_admin = true where id = ids[1];
  update public.perfiles set debe_cambiar_clave = false;
  -- Virginia es responsable de Ana, Beto y Carla (ya confirmado)
  insert into public.responsables (responsable_id, persona_id, confirmado) values (ids[2], ids[3], true), (ids[2], ids[4], true), (ids[2], ids[5], true) on conflict do nothing;
  -- Tareas de ejemplo repartidas en ~60 días (sirven para ver métricas)
  for i in 3..5 loop
    for j in 1..24 loop
      cr := ms - ((j * 2 + i) % 58) * day;
      st := case when j % 3 = 0 then 'pendiente' when j % 3 = 1 then 'completado' else 'proceso' end;
      dn := case when st = 'completado' then cr + ((j % 9) + 1) * day else 0 end;
      if dn > ms then dn := ms - day; end if;
      due := case when st = 'completado' then to_char(to_timestamp((cr + ((j % 12) + 2) * day) / 1000), 'YYYY-MM-DD')
                  else to_char(to_timestamp((ms + (((j * 3 + i) % 14) - 4) * day) / 1000), 'YYYY-MM-DD') end;  -- repartidas alrededor de hoy
      insert into public.tareas (user_id, text, status, prio, due, notes, ord, created_at, done_at, status_at, visible)
      values (ids[i], 'Tarea ' || j || ' de ' || nombres[i], st, (array['alta','media','baja',''])[1 + j % 4], due,
              case when j % 4 = 0 then 'Notas de ejemplo para la tarea ' || j else '' end, j * 1000, cr, dn, case when st = 'completado' then dn else cr end, j % 7 <> 0);
    end loop;
  end loop;
  -- Proyecto de equipo de Virginia con hitos, miembros y tareas vinculadas
  delete from public.equipo_proyectos where lider_id = ids[2];
  insert into public.equipo_proyectos (lider_id, nombre, descripcion, inicio, fin)
  values (ids[2], 'Lanzamiento Q4', 'Campaña de fin de año', to_char(now() - interval '20 days', 'YYYY-MM-DD'), to_char(now() + interval '40 days', 'YYYY-MM-DD')) returning id into pid;
  insert into public.equipo_proyecto_miembros values (pid, ids[3]), (pid, ids[4]);
  insert into public.proyecto_hitos (proyecto_id, titulo, fecha, hecho, orden) values
    (pid, 'Brief aprobado', to_char(now() - interval '10 days', 'YYYY-MM-DD'), true, 0),
    (pid, 'Primera entrega', to_char(now() + interval '3 days', 'YYYY-MM-DD'), false, 1),
    (pid, 'Revisión final', to_char(now() + interval '25 days', 'YYYY-MM-DD'), false, 2),
    (pid, 'Lanzamiento', to_char(now() + interval '40 days', 'YYYY-MM-DD'), false, 3);
  update public.tareas set equipo_proyecto_id = pid where user_id in (ids[3], ids[4]) and substring(text from 'Tarea ([0-9]+)')::int <= 8;
  insert into public.libros (user_id, titulo, resumen, categoria, alcance, paginas, enlaces)
  values (ids[2], 'Guía de bienvenida', 'Qué hacer la primera semana', 'general', 'equipo',
          '[{"t":"Introducción","b":"# Hola\nEste es un libro de ejemplo.\n- Punto uno\n- Punto dos"}]', '[{"l":"Mesa de ayuda","u":"https://ejemplo.com","k":"ayuda"}]');
end $$;
