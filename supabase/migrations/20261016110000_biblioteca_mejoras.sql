-- Biblioteca: historial de versiones y confirmación de lectura.
-- Solo agrega columnas con valor por defecto, tablas nuevas y triggers; no modifica datos existentes.

alter table public.libros
  add column if not exists version int not null default 1,
  add column if not exists requiere_lectura boolean not null default false;

-- ---------- historial de versiones ----------
create table if not exists public.libro_versiones (
  id           uuid primary key default gen_random_uuid(),
  libro_id     uuid not null references public.libros(id) on delete cascade,
  version      int not null,
  titulo       text not null,
  resumen      text not null default '',
  categoria    text not null default 'general',
  paginas      jsonb not null default '[]'::jsonb,
  enlaces      jsonb not null default '[]'::jsonb,
  guardada_at  bigint not null default (extract(epoch from now()) * 1000)::bigint,
  unique (libro_id, version)
);
create index if not exists libro_versiones_idx on public.libro_versiones (libro_id, version desc);
revoke all on public.libro_versiones from anon;
revoke truncate, references, trigger on public.libro_versiones from authenticated;
alter table public.libro_versiones enable row level security;
-- Solo el autor ve el historial; nadie escribe desde la web (lo hace el trigger).
create policy "autor ve versiones" on public.libro_versiones for select
  using (exists (select 1 from public.libros l where l.id = libro_id and l.user_id = auth.uid()));

-- Al cambiar el contenido, se guarda la versión anterior y sube el número (se conservan las últimas 20).
create or replace function public.libros_versionar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then new.version := 1; return new; end if;
  if (old.titulo, old.resumen, old.categoria, old.paginas, old.enlaces)
     is distinct from (new.titulo, new.resumen, new.categoria, new.paginas, new.enlaces) then
    insert into public.libro_versiones (libro_id, version, titulo, resumen, categoria, paginas, enlaces)
    values (old.id, old.version, old.titulo, old.resumen, old.categoria, old.paginas, old.enlaces)
    on conflict (libro_id, version) do nothing;
    delete from public.libro_versiones where libro_id = old.id and version <= old.version - 20;
    new.version := old.version + 1;
  else
    new.version := old.version;
  end if;
  return new;
end $$;
revoke execute on function public.libros_versionar() from public, anon, authenticated;
drop trigger if exists libros_versionar_t on public.libros;
create trigger libros_versionar_t before insert or update on public.libros
  for each row execute function public.libros_versionar();

-- ---------- confirmación de lectura ----------
create table if not exists public.libro_lecturas (
  libro_id    uuid not null references public.libros(id) on delete cascade,
  persona_id  uuid not null references auth.users(id) on delete cascade,
  version     int not null,
  leido_at    bigint not null default (extract(epoch from now()) * 1000)::bigint,
  primary key (libro_id, persona_id)
);
revoke all on public.libro_lecturas from anon;
revoke truncate, references, trigger on public.libro_lecturas from authenticated;
alter table public.libro_lecturas enable row level security;
create policy "ve su lectura o las de su libro" on public.libro_lecturas for select
  using (persona_id = auth.uid()
         or exists (select 1 from public.libros l where l.id = libro_id and l.user_id = auth.uid()));

create or replace function public.confirmar_lectura(p_libro uuid)
returns void language plpgsql security definer set search_path = public as $$
declare l public.libros%rowtype;
begin
  select * into l from public.libros where id = p_libro;
  if not found or not public.puede_ver_libro(l.id, l.user_id, l.alcance, l.destinatarios) then
    raise exception 'No podés confirmar la lectura de este libro.';
  end if;
  if l.user_id = auth.uid() then raise exception 'El autor no necesita confirmar la lectura.'; end if;
  insert into public.libro_lecturas (libro_id, persona_id, version) values (l.id, auth.uid(), l.version)
  on conflict (libro_id, persona_id) do update set version = excluded.version,
    leido_at = (extract(epoch from now()) * 1000)::bigint;
end $$;

-- Quiénes pueden ver el libro (para saber quién falta leerlo). Solo lo puede pedir el autor.
create or replace function public.libro_audiencia(p_libro uuid)
returns table (id uuid, nombre text) language sql stable security definer set search_path = public as $$
  select p.id, coalesce(nullif(p.nombre, ''), p.email)
  from public.libros l, public.perfiles p
  where l.id = p_libro and l.user_id = auth.uid() and p.activo and p.id <> l.user_id
    and (
      (l.alcance = 'equipo' and public.mismo_equipo(l.user_id, p.id))
      or (l.alcance = 'personas' and p.id = any (l.destinatarios) and public.mismo_equipo(l.user_id, p.id))
      or exists (
        select 1 from public.equipo_proyecto_libros pl
        join public.equipo_proyectos pr on pr.id = pl.proyecto_id
        join public.equipo_proyecto_miembros m on m.proyecto_id = pl.proyecto_id
        join public.responsables r on r.responsable_id = pr.lider_id and r.persona_id = m.persona_id
        where pl.libro_id = l.id and m.persona_id = p.id)
    )
  order by 2;
$$;

revoke all on function public.confirmar_lectura(uuid), public.libro_audiencia(uuid) from public, anon;
grant execute on function public.confirmar_lectura(uuid), public.libro_audiencia(uuid) to authenticated;
