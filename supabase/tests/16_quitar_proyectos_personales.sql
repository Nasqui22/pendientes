do $$
declare u uuid := gen_random_uuid(); pr uuid; t uuid; n int; pid uuid;
begin
  insert into auth.users (id,email,aud,role) values (u,'u@t.local','authenticated','authenticated');
  insert into proyectos (user_id, nombre) values (u, 'CROMA') returning id into pr;
  insert into tareas (user_id, text, proyecto_id) values (u, 'Tarea de CROMA', pr) returning id into t;
  -- lo que hace la migración 20261017170000: borrar los proyectos, sin tocar tareas
  delete from public.proyectos;
  select count(*) into n from tareas where id = t; if n <> 1 then raise exception 'FALLA: se borró la tarea'; end if;
  select proyecto_id into pid from tareas where id = t; if pid is not null then raise exception 'FALLA: la tarea conserva el vínculo'; end if;
  raise exception 'TODO OK (rollback)';
end $$;
