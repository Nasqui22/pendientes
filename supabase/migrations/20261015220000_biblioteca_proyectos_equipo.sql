-- Biblioteca (mini libros de páginas con enlaces) y proyectos de equipo.
--
--  * Un libro lo ve su autor; además, según `alcance`: 'equipo' (todo el equipo del autor:
--    compañeros de responsable, su responsable y sus directos) o 'personas' (una lista
--    puntual dentro de ese equipo). 'privado' = borrador solo del autor.
--  * Un líder (quien es responsable de alguien) crea proyectos de equipo, suma a sus
--    directos como miembros y asigna libros propios al proyecto. Los miembros ven los
--    libros del proyecto aunque el autor no los haya compartido de otra forma.
--  * No hay archivos: solo texto y enlaces http(s).

create or replace function public.mismo_equipo(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select a is not null and b is not null and a <> b and (
    exists (select 1 from public.responsables x join public.responsables y on x.responsable_id = y.responsable_id
            where x.persona_id = a and y.persona_id = b)
    or exists (select 1 from public.responsables r
               where (r.responsable_id = a and r.persona_id = b) or (r.responsable_id = b and r.persona_id = a))
  );
$$;

create or replace function public.es_lider()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.responsables where responsable_id = auth.uid());
$$;

create or replace function public.es_directo_mio(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.responsables where responsable_id = auth.uid() and persona_id = p);
$$;

-- ---------- tablas ----------

create table if not exists public.libros (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  titulo        text not null check (char_length(btrim(titulo)) between 1 and 120),
  resumen       text not null default '' check (char_length(resumen) <= 300),
  paginas       jsonb not null default '[]'::jsonb,
  enlaces       jsonb not null default '[]'::jsonb,
  alcance       text not null default 'privado' check (alcance in ('privado', 'equipo', 'personas')),
  destinatarios uuid[] not null default '{}',
  created_at    bigint not null default (extract(epoch from now()) * 1000)::bigint,
  updated_at    bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists libros_user_idx on public.libros (user_id);

create table if not exists public.equipo_proyectos (
  id          uuid primary key default gen_random_uuid(),
  lider_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nombre      text not null check (char_length(btrim(nombre)) between 1 and 60),
  descripcion text not null default '' check (char_length(descripcion) <= 400),
  created_at  bigint not null default (extract(epoch from now()) * 1000)::bigint
);
create index if not exists equipo_proyectos_lider_idx on public.equipo_proyectos (lider_id);

create table if not exists public.equipo_proyecto_miembros (
  proyecto_id uuid not null references public.equipo_proyectos(id) on delete cascade,
  persona_id  uuid not null references auth.users(id) on delete cascade,
  primary key (proyecto_id, persona_id)
);
create table if not exists public.equipo_proyecto_libros (
  proyecto_id uuid not null references public.equipo_proyectos(id) on delete cascade,
  libro_id    uuid not null references public.libros(id) on delete cascade,
  primary key (proyecto_id, libro_id)
);

-- ---------- ayudas de acceso (security definer: evitan recursión entre políticas) ----------

create or replace function public.es_lider_de_proyecto(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.equipo_proyectos where id = p_id and lider_id = auth.uid());
$$;

-- Miembro vigente: sigue siendo directo del líder.
create or replace function public.es_miembro_de_proyecto(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.equipo_proyecto_miembros m
    join public.equipo_proyectos p on p.id = m.proyecto_id
    join public.responsables r on r.responsable_id = p.lider_id and r.persona_id = m.persona_id
    where m.proyecto_id = p_id and m.persona_id = auth.uid()
  );
$$;

create or replace function public.puede_ver_libro(p_id uuid, p_user uuid, p_alcance text, p_dest uuid[])
returns boolean language sql stable security definer set search_path = public as $$
  select p_user = auth.uid()
    or (p_alcance = 'equipo' and public.mismo_equipo(p_user, auth.uid()))
    or (p_alcance = 'personas' and auth.uid() = any (p_dest) and public.mismo_equipo(p_user, auth.uid()))
    or exists (select 1 from public.equipo_proyecto_libros pl
               where pl.libro_id = p_id and public.es_miembro_de_proyecto(pl.proyecto_id));
$$;

-- ---------- validación del contenido ----------

create or replace function public.libros_validar()
returns trigger language plpgsql as $$
declare e jsonb; d uuid; n int;
begin
  new.titulo := btrim(new.titulo);
  new.updated_at := (extract(epoch from now()) * 1000)::bigint;
  if jsonb_typeof(new.paginas) <> 'array' or jsonb_typeof(new.enlaces) <> 'array' then
    raise exception 'Formato de libro inválido.';
  end if;
  if jsonb_array_length(new.paginas) > 12 then raise exception 'Un libro admite hasta 12 páginas.'; end if;
  if jsonb_array_length(new.enlaces) > 20 then raise exception 'Un libro admite hasta 20 enlaces.'; end if;
  for e in select * from jsonb_array_elements(new.paginas) loop
    if jsonb_typeof(e) <> 'object' or char_length(coalesce(e->>'t', '')) > 100 or char_length(coalesce(e->>'b', '')) > 10000 then
      raise exception 'Página inválida (título hasta 100 y texto hasta 10000 caracteres).';
    end if;
  end loop;
  for e in select * from jsonb_array_elements(new.enlaces) loop
    if jsonb_typeof(e) <> 'object'
       or coalesce(e->>'u', '') !~* '^https?://[^\s<>"]+$' or char_length(e->>'u') > 500
       or char_length(coalesce(e->>'l', '')) > 80
       or coalesce(e->>'k', '') not in ('automatismo', 'ejemplo', 'ayuda') then
      raise exception 'Enlace inválido: usá una URL http(s) y un tipo válido.';
    end if;
  end loop;
  if new.alcance = 'personas' then
    n := coalesce(array_length(new.destinatarios, 1), 0);
    if n = 0 then raise exception 'Elegí al menos una persona.'; end if;
    foreach d in array new.destinatarios loop
      if not public.mismo_equipo(new.user_id, d) then raise exception 'Solo podés dirigir a personas de tu equipo.'; end if;
    end loop;
  else
    new.destinatarios := '{}';
  end if;
  return new;
end $$;
drop trigger if exists libros_validar_t on public.libros;
create trigger libros_validar_t before insert or update on public.libros
  for each row execute function public.libros_validar();

-- ---------- RLS ----------

alter table public.libros enable row level security;
alter table public.equipo_proyectos enable row level security;
alter table public.equipo_proyecto_miembros enable row level security;
alter table public.equipo_proyecto_libros enable row level security;

create policy "ve libros permitidos" on public.libros for select
  using (public.puede_ver_libro(id, user_id, alcance, destinatarios));
create policy "autor crea libros"  on public.libros for insert with check (auth.uid() = user_id);
create policy "autor edita libros" on public.libros for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "autor borra libros" on public.libros for delete using (auth.uid() = user_id);

create policy "ve proyectos propios o donde participa" on public.equipo_proyectos for select
  using (lider_id = auth.uid() or public.es_miembro_de_proyecto(id));
create policy "lider crea proyectos" on public.equipo_proyectos for insert
  with check (lider_id = auth.uid() and public.es_lider());
create policy "lider edita proyectos" on public.equipo_proyectos for update
  using (lider_id = auth.uid()) with check (lider_id = auth.uid());
create policy "lider borra proyectos" on public.equipo_proyectos for delete using (lider_id = auth.uid());

create policy "ve miembros" on public.equipo_proyecto_miembros for select
  using (public.es_lider_de_proyecto(proyecto_id) or public.es_miembro_de_proyecto(proyecto_id));
create policy "lider suma directos" on public.equipo_proyecto_miembros for insert
  with check (public.es_lider_de_proyecto(proyecto_id) and public.es_directo_mio(persona_id));
create policy "lider quita miembros" on public.equipo_proyecto_miembros for delete
  using (public.es_lider_de_proyecto(proyecto_id));

create policy "ve libros del proyecto" on public.equipo_proyecto_libros for select
  using (public.es_lider_de_proyecto(proyecto_id) or public.es_miembro_de_proyecto(proyecto_id));
create policy "lider asigna sus libros" on public.equipo_proyecto_libros for insert
  with check (public.es_lider_de_proyecto(proyecto_id)
              and exists (select 1 from public.libros l where l.id = libro_id and l.user_id = auth.uid()));
create policy "lider quita libros" on public.equipo_proyecto_libros for delete
  using (public.es_lider_de_proyecto(proyecto_id));

revoke all on function public.mismo_equipo(uuid, uuid), public.es_lider(), public.es_directo_mio(uuid),
  public.es_lider_de_proyecto(uuid), public.es_miembro_de_proyecto(uuid),
  public.puede_ver_libro(uuid, uuid, text, uuid[]) from public, anon;
grant execute on function public.mismo_equipo(uuid, uuid), public.es_lider(), public.es_directo_mio(uuid),
  public.es_lider_de_proyecto(uuid), public.es_miembro_de_proyecto(uuid),
  public.puede_ver_libro(uuid, uuid, text, uuid[]) to authenticated;
