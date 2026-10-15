-- Pegar en Supabase > SQL Editor > Run
create table if not exists public.tareas (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  text        text   not null default '',
  status      text   not null default 'pendiente' check (status in ('pendiente','proceso','completado')),
  prio        text   not null default '',
  due         text   not null default '',
  notes       text   not null default '',
  subs        jsonb  not null default '[]'::jsonb,
  ord         bigint not null default 0,
  created_at  bigint not null default 0,
  done_at     bigint not null default 0
);

alter table public.tareas enable row level security;

create policy "dueño lee"     on public.tareas for select using (auth.uid() = user_id);
create policy "dueño inserta" on public.tareas for insert with check (auth.uid() = user_id);
create policy "dueño edita"   on public.tareas for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "dueño borra"   on public.tareas for delete using (auth.uid() = user_id);

-- Para que la página reciba cambios en vivo
alter publication supabase_realtime add table public.tareas;
