do $$
declare a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); n int; r record; i int;
begin
  insert into auth.users (id,email,aud,role) values (a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated');

  -- ===== sin secreto `pa_url` no se envía nada =====
  perform notificar(a, b, 'tareas', 'tarea_asignada', 'Te asignaron una tarea', 'x', 'tarea', gen_random_uuid());
  select count(*) into n from correos_enviados where para_id = a; if n <> 0 then raise exception 'FALLA: registró envío sin pa_url (%)', n; end if;

  -- ===== con el secreto, cada aviso nuevo genera un envío =====
  perform vault.create_secret('http://127.0.0.1:9/prueba', 'pa_url');
  perform vault.create_secret('token-de-prueba', 'pa_token');
  perform notificar(a, b, 'tareas', 'tarea_asignada', 'Te asignaron una tarea', 'secreto', 'tarea', gen_random_uuid());
  select * into r from correos_enviados where para_id = a order by id desc limit 1;
  if r.estado is distinct from 'enviado' or r.request_id is null then raise exception 'FALLA: no encoló el correo (%)', r.estado; end if;
  select count(*) into n from net.http_request_queue where url = 'http://127.0.0.1:9/prueba' and convert_from(body, 'utf8') like '%a@t.local%';
  if n <> 1 then raise exception 'FALLA: no se encoló un POST para a@t.local (%)', n; end if;
  -- el correo lleva el título y el detalle del aviso, y el nombre de quien lo generó
  select count(*) into n from net.http_request_queue where convert_from(body, 'utf8') like '%Te asignaron una tarea%' and convert_from(body, 'utf8') like '%secreto%'; if n <> 1 then raise exception 'FALLA: el correo no lleva título y detalle (%)', n; end if;
  -- el texto de usuarios se escapa: no entra HTML ajeno al correo
  perform notificar(a, b, 'comentarios', 'comentario', '<script>alert(1)</script>', '<img src=x onerror=alert(1)>' || E'\n' || 'línea 2', 'tarea', gen_random_uuid());
  select count(*) into n from net.http_request_queue where convert_from(body, 'utf8') like '%<script>%' or convert_from(body, 'utf8') like '%<img src=x%'; if n <> 0 then raise exception 'FALLA: el correo deja pasar HTML de usuarios (%)', n; end if;
  select count(*) into n from net.http_request_queue where convert_from(body, 'utf8') like '%&lt;script&gt;%' and convert_from(body, 'utf8') like '%línea 2%'; if n < 1 then raise exception 'FALLA: el correo no escapó el texto'; end if;
  delete from correos_enviados where para_id = a;
  -- el token viaja en el encabezado
  select count(*) into n from net.http_request_queue where url = 'http://127.0.0.1:9/prueba' and headers::text like '%token-de-prueba%'; if n <> 1 then raise exception 'FALLA: falta el token en el encabezado'; end if;

  -- ===== quien apagó el correo no recibe =====
  insert into notif_prefs (persona_id, correo) values (a, false);
  perform notificar(a, b, 'tareas', 'tarea_asignada', 'Otra', 'x', 'tarea', gen_random_uuid());
  select count(*) into n from correos_enviados where para_id = a; if n <> 1 then raise exception 'FALLA: envió con el correo apagado (%)', n; end if;

  -- ===== los grupos silenciados no generan aviso ni correo =====
  update notif_prefs set correo = true, silenciadas = array['equipo'] where persona_id = a;
  perform notificar(a, b, 'equipo', 'x', 'Silenciado', 'x', 'tarea', gen_random_uuid());
  select count(*) into n from correos_enviados where para_id = a; if n <> 1 then raise exception 'FALLA: envió un grupo silenciado (%)', n; end if;

  -- ===== tope de 20 por hora y por persona =====
  for i in 1..25 loop perform notificar(a, b, 'tareas', 'tarea_asignada', 'T' || i, 'x', 'tarea', gen_random_uuid()); end loop;
  select count(*) into n from correos_enviados where para_id = a and estado = 'enviado'; if n <> 20 then raise exception 'FALLA: el tope por persona no frena en 20 (%)', n; end if;
  select count(*) into n from correos_enviados where para_id = a and estado = 'limite'; if n < 1 then raise exception 'FALLA: no registró el límite'; end if;

  -- ===== un usuario común no ve ni toca el registro ni el secreto =====
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform count(*) from correos_enviados; raise exception 'FALLA: leyó correos_enviados'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform decrypted_secret from vault.decrypted_secrets; raise exception 'FALLA: leyó el vault'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform trg_correo_aviso(); raise exception 'FALLA: ejecutó la función de trigger'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  set local role anon;
  begin perform count(*) from correos_enviados; raise exception 'FALLA: anon leyó correos_enviados'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;

  -- ===== un fallo del envío no impide crear el aviso =====
  perform vault.update_secret((select id from vault.secrets where name = 'pa_url'), 'esto no es una url');
  select count(*) into n from notificaciones where para_id = b;
  perform notificar(b, a, 'tareas', 'tarea_asignada', 'Aviso con URL rota', 'x', 'tarea', gen_random_uuid());
  select count(*) into i from notificaciones where para_id = b; if i <> n + 1 then raise exception 'FALLA: un error de correo bloqueó el aviso'; end if;

  raise exception 'TODO OK (rollback)';
end $$;
