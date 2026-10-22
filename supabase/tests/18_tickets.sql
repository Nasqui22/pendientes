do $$
declare s uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); x uuid := gen_random_uuid();
        sv uuid; sv0 uuid; tk uuid; n int; r record;
begin
  insert into auth.users (id,email,aud,role) values (s,'s@t.local','authenticated','authenticated'),(a,'a@t.local','authenticated','authenticated'),(b,'b@t.local','authenticated','authenticated'),(x,'x@t.local','authenticated','authenticated');
  update perfiles set nombre = 'Santiago' where id = s; update perfiles set nombre = 'Ana' where id = a;
  insert into servicios (clave, nombre, responsable_id) values ('prueba', 'Prueba', s) returning id into sv;
  insert into servicios (clave, nombre) values ('sinresp', 'Sin responsable') returning id into sv0;

  -- ===== Ana crea un ticket =====
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into tickets (servicio_id, titulo, prioridad, contexto, entorno_url, entorno_tipo, criticidad, caso_ejemplo)
    values (sv, 'No carga el reporte', 'alta', 'Desde ayer', 'https://merlin.test/reporte', 'produccion', 'alta', 'Entro a Reportes y queda en blanco')
    returning id into tk;
  reset role;
  select * into r from tickets where id = tk;
  if r.estado <> 'nuevo' or r.solicitante_nombre <> 'Ana' or r.numero is null then raise exception 'FALLA: ticket mal armado (%)', r.estado; end if;
  select count(*) into n from notificaciones where para_id = s and tipo = 'ticket_nuevo' and ref_id = tk; if n <> 1 then raise exception 'FALLA: no avisó al responsable (%)', n; end if;
  select count(*) into n from notificaciones where para_id = a and tipo = 'ticket_nuevo'; if n <> 0 then raise exception 'FALLA: avisó al solicitante'; end if;

  -- ===== validaciones del servidor =====
  set local role authenticated;
  begin insert into tickets (servicio_id, titulo, contexto, entorno_url, entorno_tipo, criticidad, caso_ejemplo) values (sv, 'x', 'c', 'javascript:alert(1)', 'produccion', 'alta', 'e'); raise exception 'FALLA: aceptó una URL no http'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tickets (servicio_id, titulo, contexto, entorno_url, entorno_tipo, criticidad, caso_ejemplo) values (sv, 'x', 'c', 'https://a.test', 'cualquiera', 'alta', 'e'); raise exception 'FALLA: aceptó un entorno inválido'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tickets (servicio_id, titulo, contexto, entorno_url, entorno_tipo, criticidad, caso_ejemplo) values (sv, '  ', 'c', 'https://a.test', 'pruebas', 'alta', 'e'); raise exception 'FALLA: aceptó título vacío'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into tickets (servicio_id, titulo, contexto, entorno_url, entorno_tipo, criticidad, caso_ejemplo) values (sv0, 'x', 'c', 'https://a.test', 'pruebas', 'alta', 'e'); raise exception 'FALLA: creó ticket en un servicio sin responsable'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  -- no puede inventar estado ni suplantar a otra persona
  begin insert into tickets (servicio_id, solicitante_id, titulo, contexto, entorno_url, entorno_tipo, criticidad, caso_ejemplo) values (sv, b, 'x', 'c', 'https://a.test', 'pruebas', 'alta', 'e'); raise exception 'FALLA: creó un ticket a nombre de otro'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  insert into tickets (servicio_id, titulo, contexto, entorno_url, entorno_tipo, criticidad, caso_ejemplo, estado) values (sv, 'Con estado', 'c', 'https://a.test', 'pruebas', 'baja', 'e', 'cerrado');
  reset role;
  select count(*) into n from tickets where titulo = 'Con estado' and estado = 'nuevo'; if n <> 1 then raise exception 'FALLA: se pudo crear un ticket con otro estado'; end if;
  delete from tickets where titulo = 'Con estado';

  -- ===== visibilidad: solo solicitante y responsable =====
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from tickets; if n <> 0 then raise exception 'FALLA: un tercero ve tickets'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', s, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from tickets where id = tk; if n <> 1 then raise exception 'FALLA: el responsable no ve el ticket'; end if;
  reset role;

  -- ===== el solicitante edita el contenido mientras es «nuevo» =====
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update tickets set titulo = 'No carga el reporte mensual' where id = tk;
  begin update tickets set estado = 'cerrado' where id = tk; raise exception 'FALLA: cambió el estado directo'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin update tickets set solicitante_id = b where id = tk; raise exception 'FALLA: cambió el solicitante'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin delete from tickets where id = tk; raise exception 'FALLA: borró un ticket'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  select titulo into r from tickets where id = tk; if r.titulo <> 'No carga el reporte mensual' then raise exception 'FALLA: no se editó el título'; end if;
  -- el responsable no edita el contenido
  perform set_config('request.jwt.claims', json_build_object('sub', s, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update tickets set titulo = 'Cambiado por el responsable' where id = tk;
  reset role;
  select titulo into r from tickets where id = tk; if r.titulo = 'Cambiado por el responsable' then raise exception 'FALLA: el responsable editó el contenido'; end if;

  -- ===== flujo de estados =====
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform cambiar_estado_ticket(tk, 'resuelto'); raise exception 'FALLA: el solicitante resolvió'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform cambiar_estado_ticket(tk, 'en_curso'); raise exception 'FALLA: un tercero cambió el estado'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', s, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform cambiar_estado_ticket(tk, 'en_curso');
  reset role;
  select count(*) into n from notificaciones where para_id = a and tipo = 'ticket_en_curso'; if n <> 1 then raise exception 'FALLA: no avisó el pase a en curso'; end if;
  -- ya no es «nuevo»: Ana no edita más
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update tickets set titulo = 'Tarde' where id = tk;
  reset role;
  select titulo into r from tickets where id = tk; if r.titulo = 'Tarde' then raise exception 'FALLA: editó un ticket en curso'; end if;
  -- el responsable no puede cerrar
  perform set_config('request.jwt.claims', json_build_object('sub', s, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform cambiar_estado_ticket(tk, 'cerrado'); raise exception 'FALLA: el responsable cerró'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  perform cambiar_estado_ticket(tk, 'resuelto');
  reset role;
  select * into r from tickets where id = tk; if r.estado <> 'resuelto' or r.resuelto_at = 0 then raise exception 'FALLA: no quedó resuelto'; end if;
  select count(*) into n from notificaciones where para_id = a and tipo = 'ticket_resuelto'; if n <> 1 then raise exception 'FALLA: no avisó la resolución'; end if;
  -- Ana reabre y el responsable vuelve a resolver
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated; perform cambiar_estado_ticket(tk, 'en_curso'); reset role;
  select * into r from tickets where id = tk; if r.estado <> 'en_curso' or r.resuelto_at <> 0 then raise exception 'FALLA: no reabrió'; end if;
  select count(*) into n from notificaciones where para_id = s and tipo = 'ticket_reabierto'; if n <> 1 then raise exception 'FALLA: no avisó la reapertura'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', s, 'role', 'authenticated')::text, true);
  set local role authenticated; perform cambiar_estado_ticket(tk, 'resuelto'); reset role;

  -- ===== comentarios =====
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into ticket_comentarios (ticket_id, texto) values (tk, 'Sigue pasando'); insert into ticket_comentarios (ticket_id, texto) values (tk, 'Y en otro equipo');
  begin update ticket_comentarios set texto = 'editado' where ticket_id = tk; if found then raise exception 'FALLA: editó un comentario'; end if; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin insert into ticket_comentarios (ticket_id, autor_id, texto) values (tk, b, 'suplanto'); raise exception 'FALLA: comentó como otro'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  select count(*), max(cantidad) into n, r.numero from notificaciones where para_id = s and tipo = 'ticket_comentario' and ref_id = tk and not leida;
  if n <> 1 or r.numero <> 2 then raise exception 'FALLA: comentarios sin agrupar (n=%, cant=%)', n, r.numero; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from ticket_comentarios; if n <> 0 then raise exception 'FALLA: un tercero lee comentarios'; end if;
  begin insert into ticket_comentarios (ticket_id, texto) values (tk, 'intruso'); raise exception 'FALLA: un tercero comentó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;

  -- ===== cierre: solo el solicitante, y después ya no se comenta =====
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated; perform cambiar_estado_ticket(tk, 'cerrado');
  begin insert into ticket_comentarios (ticket_id, texto) values (tk, 'tarde'); raise exception 'FALLA: comentó en un ticket cerrado'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform cambiar_estado_ticket(tk, 'en_curso'); raise exception 'FALLA: reabrió un ticket cerrado'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  select count(*) into n from notificaciones where para_id = s and tipo = 'ticket_cerrado'; if n <> 1 then raise exception 'FALLA: no avisó el cierre'; end if;

  -- ===== servicios: solo por la función, y límites =====
  set local role authenticated;
  select count(*) into n from servicios_lista() where responsable_nombre = 'Santiago'; if n <> 1 then raise exception 'FALLA: servicios_lista no muestra al responsable'; end if;
  select count(*) into n from servicios; if n <> 0 then raise exception 'FALLA: lectura directa de servicios'; end if;
  begin update servicios set responsable_id = a; if found then raise exception 'FALLA: cambió el responsable'; end if; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated')::text, true);
  set local role authenticated;
  for n in 1..10 loop
    insert into tickets (servicio_id, titulo, contexto, entorno_url, entorno_tipo, criticidad, caso_ejemplo) values (sv, 'T' || n, 'c', 'https://a.test', 'pruebas', 'baja', 'e');
  end loop;
  begin
    insert into tickets (servicio_id, titulo, contexto, entorno_url, entorno_tipo, criticidad, caso_ejemplo) values (sv, 'T11', 'c', 'https://a.test', 'pruebas', 'baja', 'e');
    raise exception 'FALLA: sin límite de tickets por hora';
  exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  -- anon no ejecuta ni lee
  set local role anon;
  begin perform cambiar_estado_ticket(tk, 'en_curso'); raise exception 'FALLA: anon ejecutó'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform count(*) from tickets; raise exception 'FALLA: anon lee tickets'; exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  reset role;
  raise exception 'TODO OK (rollback)';
end $$;
