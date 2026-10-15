-- Etapa 1: perfiles de usuario (nombre, admin, activo) vinculados a auth.users.
-- Solo se agregan objetos nuevos; no se modifica ni borra nada de `tareas`.

create table public.perfiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text    not null default '',
  nombre      text    not null default '',
  es_admin    boolean not null default false,
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

alter table public.perfiles enable row level security;

-- ¿El usuario actual es un administrador activo? security definer evita
-- que la política de `perfiles` se consulte a sí misma en bucle.
create or replace function public.es_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce((select p.es_admin and p.activo from public.perfiles p where p.id = auth.uid()), false);
$$;
revoke all on function public.es_admin() from public;
grant execute on function public.es_admin() to authenticated;

-- Cada usuario ve su propio perfil; el admin ve todos.
-- No hay políticas de insert/update/delete: todo cambio pasa por la Edge
-- Function `admin-usuarios`, que verifica que quien llama sea admin.
create policy "perfil propio o admin lee" on public.perfiles
  for select to authenticated
  using (id = auth.uid() or public.es_admin());

-- Cada usuario nuevo de Auth recibe su perfil automáticamente.
create or replace function public.crear_perfil()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.perfiles (id, email, nombre)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(nullif(new.raw_user_meta_data->>'nombre', ''), split_part(coalesce(new.email, ''), '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger al_crear_usuario
  after insert on auth.users
  for each row execute function public.crear_perfil();

-- Perfiles para los usuarios que ya existen (ninguno queda como admin).
insert into public.perfiles (id, email, nombre)
select u.id, coalesce(u.email, ''), split_part(coalesce(u.email, ''), '@', 1)
from auth.users u
on conflict (id) do nothing;
