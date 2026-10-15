-- Etapa 2: quién es responsable de quién.
-- Una persona puede tener varios responsables y un responsable puede tener
-- a su vez otros responsables (cadena). Solo el admin asigna y quita.
-- Solo agrega objetos nuevos; no toca `tareas` ni `perfiles`.

create table public.responsables (
  responsable_id uuid not null references public.perfiles(id) on delete cascade,
  persona_id     uuid not null references public.perfiles(id) on delete cascade,
  created_at     timestamptz not null default now(),
  primary key (responsable_id, persona_id),
  check (responsable_id <> persona_id)
);
create index responsables_persona_idx on public.responsables (persona_id);

alter table public.responsables enable row level security;

-- Cada uno ve las relaciones donde participa; el admin ve todas.
create policy "ve admin o involucrado" on public.responsables
  for select to authenticated
  using (public.es_admin() or responsable_id = auth.uid() or persona_id = auth.uid());

create policy "admin asigna" on public.responsables
  for insert to authenticated
  with check (public.es_admin());

create policy "admin quita" on public.responsables
  for delete to authenticated
  using (public.es_admin());

-- Sin ciclos: no se puede nombrar responsable a alguien que ya depende
-- (directa o indirectamente) de la persona.
create or replace function public.evitar_ciclo_responsables()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if exists (
    with recursive arriba(id) as (
      select r.responsable_id from public.responsables r where r.persona_id = new.responsable_id
      union
      select r.responsable_id from public.responsables r join arriba a on r.persona_id = a.id
    )
    select 1 from arriba where id = new.persona_id
  ) then
    raise exception 'Esa asignación crearía un ciclo entre responsables';
  end if;
  return new;
end;
$$;

create trigger evitar_ciclo
  before insert on public.responsables
  for each row execute function public.evitar_ciclo_responsables();
