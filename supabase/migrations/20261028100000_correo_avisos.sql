-- Avisos por correo: cada notificación nueva dispara un POST a un flujo de Power Automate, que envía el correo.
-- La URL del flujo y el token compartido viven en Supabase Vault (nunca en el repo):
--   select vault.create_secret('<URL del disparador HTTP>', 'pa_url');
--   select vault.create_secret('<token compartido>', 'pa_token');
-- Sin el secreto `pa_url` el trigger no hace nada (así en local no se envía nada).
-- El correo no lleva el contenido del aviso: solo el grupo y un enlace a la web.

create extension if not exists pg_net;

-- Cada persona puede apagar el correo (por defecto llega). Los grupos silenciados ya no generan aviso, ni correo.
alter table public.notif_prefs add column if not exists correo boolean not null default true;

-- Registro de envíos: sirve para el tope por hora y para diagnosticar. Sin políticas: solo service_role.
create table if not exists public.correos_enviados (
  id              bigint generated always as identity primary key,
  notificacion_id uuid,
  para_id         uuid not null,
  estado          text not null check (estado in ('enviado', 'limite', 'error')),
  request_id      bigint,
  detalle         text not null default '',
  created_at      timestamptz not null default now()
);
create index if not exists correos_enviados_para_idx on public.correos_enviados (para_id, created_at desc);
revoke all on public.correos_enviados from anon, authenticated;
alter table public.correos_enviados enable row level security;

create or replace function public.trg_correo_aviso()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_url text; v_token text; v_mail text; v_correo boolean; n int; v_req bigint;
  v_grupo text := case new.grupo
    when 'tareas' then 'Tareas' when 'comentarios' then 'Comentarios' when 'biblioteca' then 'Biblioteca'
    when 'proyectos' then 'Proyectos' when 'equipo' then 'Equipo' when 'tickets' then 'Tickets' else 'Avisos' end;
begin
  begin
    select decrypted_secret into v_url from vault.decrypted_secrets where name = 'pa_url';
    if v_url is null then return new; end if;
    select decrypted_secret into v_token from vault.decrypted_secrets where name = 'pa_token';
    select email into v_mail from public.perfiles where id = new.para_id and activo;
    if coalesce(v_mail, '') = '' then return new; end if;
    select correo into v_correo from public.notif_prefs where persona_id = new.para_id;
    if v_correo is false then return new; end if;

    delete from public.correos_enviados where created_at < now() - interval '30 days';
    select count(*) into n from public.correos_enviados where para_id = new.para_id and created_at > now() - interval '1 hour';
    if n >= 20 then
      insert into public.correos_enviados (notificacion_id, para_id, estado, detalle) values (new.id, new.para_id, 'limite', 'Más de 20 correos en una hora');
      return new;
    end if;
    select count(*) into n from public.correos_enviados where created_at > now() - interval '1 hour';
    if n >= 300 then
      insert into public.correos_enviados (notificacion_id, para_id, estado, detalle) values (new.id, new.para_id, 'limite', 'Más de 300 correos en una hora');
      return new;
    end if;

    v_req := net.http_post(
      url := v_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-merlint-token', coalesce(v_token, '')),
      body := jsonb_build_object(
        'para', v_mail,
        'asunto', 'Merlin''t: tenés un aviso nuevo (' || v_grupo || ')',
        'cuerpo', '<p>Tenés un aviso nuevo en Merlin''t (' || v_grupo || ').</p>'
               || '<p><a href="https://nasqui22.github.io/pendientes/">Abrir Merlin''t</a></p>'
               || '<p style="color:#888;font-size:12px">Podés apagar los correos desde Preferencias de avisos.</p>',
        'grupo', new.grupo,
        'ref', new.id),
      timeout_milliseconds := 5000);
    insert into public.correos_enviados (notificacion_id, para_id, estado, request_id) values (new.id, new.para_id, 'enviado', v_req);
  exception when others then
    -- un fallo de correo nunca debe impedir que se cree el aviso
    insert into public.correos_enviados (notificacion_id, para_id, estado, detalle) values (new.id, new.para_id, 'error', left(sqlerrm, 200));
  end;
  return new;
end $$;
revoke execute on function public.trg_correo_aviso() from public, anon, authenticated;
drop trigger if exists trg_correo_aviso_i on public.notificaciones;
create trigger trg_correo_aviso_i after insert on public.notificaciones for each row execute function public.trg_correo_aviso();
