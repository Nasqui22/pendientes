-- Cambio de contraseña obligatorio en el primer ingreso (y cuando un admin la restablece).
-- El indicador solo lo escribe la Edge Function (service_role) o la persona al terminar el
-- cambio, mediante `clave_cambiada()`.

alter table public.perfiles
  add column if not exists debe_cambiar_clave boolean not null default false;

create or replace function public.clave_cambiada()
returns void language sql security definer set search_path = public as $$
  update public.perfiles set debe_cambiar_clave = false where id = auth.uid();
$$;
revoke all on function public.clave_cambiada() from public, anon;
grant execute on function public.clave_cambiada() to authenticated;

-- Cuentas de colegas que todavía usan la contraseña que les dio el administrador.
update public.perfiles set debe_cambiar_clave = true
 where email in ('esuarez@megalabs.global', 'rbarbitta@megalabs.global', 'srisi@megalabs.global', 'vhernandez@megalabs.global');
