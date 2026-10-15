// Gestión de usuarios para el panel de administración.
// Corre en el servidor de Supabase: SUPABASE_SERVICE_ROLE_KEY la inyecta la
// plataforma, nunca va en el repo ni en la web.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.117.3";

// Solo la web publicada y el servidor local pueden llamar desde un navegador.
const ORIGENES = ["https://nasqui22.github.io", "http://localhost:8000", "http://127.0.0.1:8000"];

function corsFor(req: Request): Record<string, string> {
  const o = req.headers.get("Origin") ?? "";
  return {
    ...(ORIGENES.includes(o) ? { "Access-Control-Allow-Origin": o } : {}),
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "no-store",
  };
}

let cors: Record<string, string> = {};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{1,63}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_POR_MINUTO = 20; // límite de acciones de administración por admin

Deno.serve(async (req) => {
  cors = corsFor(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // Quién llama, y si es admin activo.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: u, error: eu } = await sb.auth.getUser(token);
  if (eu || !u.user) return json({ error: "No autenticado" }, 401);
  const { data: yo } = await sb.from("perfiles").select("es_admin, activo").eq("id", u.user.id).maybeSingle();
  if (!yo?.es_admin || !yo.activo) return json({ error: "Solo un administrador puede hacer esto" }, 403);

  // Límite de uso y registro de cada acción.
  const desde = new Date(Date.now() - 60_000).toISOString();
  const { count } = await sb.from("admin_acciones").select("id", { count: "exact", head: true })
    .eq("admin_id", u.user.id).gte("created_at", desde);
  if ((count ?? 0) >= MAX_POR_MINUTO) return json({ error: "Demasiadas acciones seguidas. Esperá un minuto." }, 429);

  let p: Record<string, unknown>;
  try { p = await req.json(); } catch { return json({ error: "Pedido inválido" }, 400); }

  const registrar = async (accion: string, objetivo?: string) => {
    await sb.from("admin_acciones").insert({ admin_id: u.user.id, accion, objetivo: objetivo ?? null });
  };
  const nombre = typeof p.nombre === "string" ? p.nombre.trim().slice(0, 80) : undefined;
  const password = typeof p.password === "string" ? p.password : undefined;

  if (p.accion === "crear") {
    const email = typeof p.email === "string" ? p.email.trim().toLowerCase() : "";
    if (!EMAIL.test(email)) return json({ error: "Email inválido" }, 400);
    if (!password || password.length < 8 || password.length > 72) return json({ error: "La contraseña debe tener entre 8 y 72 caracteres" }, 400);
    const { data, error } = await sb.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { nombre: nombre ?? "" },
    });
    if (error || !data.user) return json({ error: error?.message ?? "No se pudo crear el usuario" }, 400);
    // El trigger ya creó el perfil; acá se completan los datos elegidos.
    const { error: ep } = await sb.from("perfiles")
      .update({ ...(nombre ? { nombre } : {}), es_admin: p.es_admin === true, debe_cambiar_clave: true })
      .eq("id", data.user.id);
    if (ep) return json({ error: ep.message }, 500);
    await registrar(p.es_admin === true ? "crear_admin" : "crear", data.user.id);
    return json({ ok: true, id: data.user.id });
  }

  if (p.accion === "actualizar" || p.accion === "clave") {
    const id = typeof p.id === "string" ? p.id : "";
    if (!UUID.test(id)) return json({ error: "Usuario inválido" }, 400);
    const { data: objetivo } = await sb.from("perfiles").select("id").eq("id", id).maybeSingle();
    if (!objetivo) return json({ error: "El usuario no existe" }, 404);

    if (p.accion === "clave") {
      if (!password || password.length < 8 || password.length > 72) return json({ error: "La contraseña debe tener entre 8 y 72 caracteres" }, 400);
      const { error } = await sb.auth.admin.updateUserById(id, { password });
      if (error) return json({ error: error.message }, 400);
      // La contraseña la eligió un admin: la persona debe cambiarla al entrar (salvo que el admin cambie la suya).
      if (id !== u.user.id) await sb.from("perfiles").update({ debe_cambiar_clave: true }).eq("id", id);
      await registrar("clave", id);
      return json({ ok: true });
    }

    // Un admin no puede quitarse a sí mismo el permiso ni desactivarse.
    if (id === u.user.id && (p.es_admin === false || p.activo === false)) {
      return json({ error: "No podés quitarte el rol de admin ni desactivarte a vos mismo" }, 400);
    }
    const cambios: Record<string, unknown> = {};
    if (nombre !== undefined) cambios.nombre = nombre;
    if (typeof p.es_admin === "boolean") cambios.es_admin = p.es_admin;
    if (typeof p.activo === "boolean") {
      // Desactivar bloquea el ingreso en Auth; activar lo habilita de nuevo.
      const { error } = await sb.auth.admin.updateUserById(id, { ban_duration: p.activo ? "none" : "876000h" });
      if (error) return json({ error: error.message }, 400);
      cambios.activo = p.activo;
    }
    if (!Object.keys(cambios).length) return json({ error: "Nada para actualizar" }, 400);
    const { error } = await sb.from("perfiles").update(cambios).eq("id", id);
    if (error) return json({ error: error.message }, 500);
    await registrar("actualizar", id);
    return json({ ok: true });
  }

  return json({ error: "Acción desconocida" }, 400);
});
