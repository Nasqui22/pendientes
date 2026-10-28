-- Correo de avisos con más información: quién lo generó, el título y el detalle del aviso, y un botón a la web.
-- Reemplaza el cuerpo de trg_correo_aviso (migración 20261028100000); no cambia datos ni el contrato con el flujo.
-- Todo texto de usuarios se escapa antes de entrar al HTML.

create or replace function public.html_esc(p text)
returns text language sql immutable set search_path = public as $$
  select replace(replace(replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');
$$;
revoke execute on function public.html_esc(text) from public, anon, authenticated;

create or replace function public.trg_correo_aviso()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_url text; v_token text; v_mail text; v_correo boolean; n int; v_req bigint; v_html text; v_de text; v_cuando text;
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

    v_de := case when new.de_id is not null then public.nombre_de(new.de_id) end;
    v_cuando := to_char(to_timestamp(new.created_at / 1000.0) at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI');

    v_html :=
      '<div style="margin:0;padding:24px 12px;background:#F6F7F9;font-family:''Segoe UI'',Helvetica,Arial,sans-serif">'
      || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;margin:0 auto;background:#FFFFFF;border:1px solid #E2E6EC;border-radius:12px;overflow:hidden">'
      || '<tr><td style="background:#3858E9;padding:16px 24px;color:#FFFFFF;font-size:18px;font-weight:700;letter-spacing:.2px">Merlin''t</td></tr>'
      || '<tr><td style="padding:24px 24px 8px">'
      ||   '<span style="display:inline-block;background:#E9EEFF;color:#3858E9;font-size:12px;font-weight:700;padding:3px 10px;border-radius:999px">' || public.html_esc(v_grupo) || '</span>'
      ||   '<span style="color:#667085;font-size:12px;margin-left:8px">' || v_cuando || '</span>'
      || '</td></tr>'
      || '<tr><td style="padding:8px 24px 0;color:#12151C;font-size:20px;line-height:1.3;font-weight:700">' || public.html_esc(new.titulo) || '</td></tr>'
      || case when v_de is not null then '<tr><td style="padding:6px 24px 0;color:#4B5565;font-size:14px">De <strong>' || public.html_esc(v_de) || '</strong></td></tr>' else '' end
      || case when coalesce(new.cuerpo, '') <> '' then
           '<tr><td style="padding:16px 24px 0"><div style="background:#F6F7F9;border-left:3px solid #3858E9;border-radius:6px;padding:12px 14px;color:#12151C;font-size:15px;line-height:1.5">'
           || replace(public.html_esc(new.cuerpo), E'\n', '<br>') || '</div></td></tr>' else '' end
      || '<tr><td style="padding:24px"><a href="https://nasqui22.github.io/pendientes/" style="display:inline-block;background:#3858E9;color:#FFFFFF;text-decoration:none;font-size:15px;font-weight:600;padding:12px 22px;border-radius:8px">Abrir en Merlin''t</a></td></tr>'
      || '<tr><td style="padding:14px 24px;border-top:1px solid #E2E6EC;color:#667085;font-size:12px;line-height:1.5">Recibís este correo porque tenés activados los avisos por correo. Podés apagarlos en Merlin''t, en Preferencias de avisos.</td></tr>'
      || '</table></div>';

    v_req := net.http_post(
      url := v_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-merlint-token', coalesce(v_token, '')),
      body := jsonb_build_object(
        'para', v_mail,
        'asunto', 'Merlin''t · ' || left(regexp_replace(new.titulo, '[\r\n]+', ' ', 'g'), 120),
        'cuerpo', v_html,
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
