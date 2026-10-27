// =================================================================
//  USUARIOS
//  - primer_admin: la primera vez que se abre la app se crea el
//    administrador (solo si todavía no hay ningún usuario).
//  - crear / activar / clave: el administrador maneja a los vendedores.
//  Necesita la clave de servicio (solo existe en el servidor), por eso no se
//  hace desde la app. Cada pedido verifica quién llama.
//  Se publica con verify_jwt = false porque primer_admin se usa sin sesión;
//  las demás acciones validan el token acá adentro.
// =================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

// Se entra con un usuario (ej: "juan.perez"). Por dentro se usa un email con
// un dominio reservado que nunca recibe correos (.invalid).
const DOMINIO = "usuarios.sistema-pedidos.invalid";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const responder = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const error = (status: number, mensaje: string) => responder(status, { error: mensaje });

const limpiar = (v: unknown) => (typeof v === "string" ? v.replace(/\s+/g, " ").trim() : "");
const nombreOk = (v: string) => v.length >= 3 && v.length <= 80;
const usuarioOk = (v: string) => /^[a-z0-9._-]{3,30}$/.test(v);
const claveOk = (v: unknown): v is string => typeof v === "string" && v.length >= 6 && v.length <= 72;
const emailOk = (v: string) => v.length <= 100 && /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(v);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return error(405, "Método no permitido.");

  const url = Deno.env.get("SUPABASE_URL")!;
  const servicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, servicio, { auth: { persistSession: false, autoRefreshToken: false } });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return error(400, "Pedido inválido.");
  }

  const auditar = (usuarioId: string | null, usuarioNombre: string, accion: string, detalle: string) =>
    admin.from("historial").insert({ usuario_id: usuarioId, usuario_nombre: usuarioNombre, area: "Usuarios", accion, detalle, importante: true });

  // Crea el usuario en Auth y su fila de miembro (sin dejar nada a medias).
  // [email]: si la persona entra con su email real (ej: el administrador); si no, se usa el interno.
  const alta = async (nombre: string, usuario: string, clave: string, rol: "admin" | "vendedor", email?: string) => {
    const { data: existe } = await admin.from("miembros").select("user_id").eq("usuario", usuario).maybeSingle();
    if (existe) return { error: error(409, `Ya existe un usuario "${usuario}".`) };
    const { data: creado, error: e1 } = await admin.auth.admin.createUser({
      email: email || `${usuario}@${DOMINIO}`,
      password: clave,
      email_confirm: true,
      user_metadata: { full_name: nombre },
      app_metadata: { role: rol },
    });
    if (e1 || !creado.user) {
      const ya = (e1?.message ?? "").toLowerCase().includes("already");
      return { error: error(ya ? 409 : 400, ya ? `Ya existe un usuario "${usuario}".` : "No se pudo crear el usuario.") };
    }
    const { error: e2 } = await admin.from("miembros").insert({ user_id: creado.user.id, nombre, usuario, rol, activo: true });
    if (e2) {
      await admin.auth.admin.deleteUser(creado.user.id);
      return { error: error(400, "No se pudo registrar el usuario. Intentá de nuevo.") };
    }
    return { id: creado.user.id };
  };

  // ---------- Primer uso: crear el administrador ----------
  if (body.accion === "primer_admin") {
    const { count } = await admin.from("miembros").select("user_id", { count: "exact", head: true });
    if ((count ?? 0) > 0) return error(409, "La app ya tiene un administrador. Ingresá con tu usuario.");
    const nombre = limpiar(body.nombre);
    const usuario = limpiar(body.usuario).toLowerCase();
    const email = limpiar(body.email).toLowerCase();
    if (!nombreOk(nombre)) return error(400, "Escribí el nombre y apellido.");
    if (!usuarioOk(usuario)) return error(400, "El usuario solo puede tener letras, números, punto o guion (ej: juan.perez).");
    if (email && !emailOk(email)) return error(400, "Ese email no es válido.");
    if (!claveOk(body.clave)) return error(400, "La contraseña tiene que tener al menos 6 caracteres.");
    const r = await alta(nombre, usuario, body.clave, "admin", email || undefined);
    if (r.error) return r.error;
    // Proveedor por defecto (para que el consolidado funcione desde el primer día).
    const { count: provs } = await admin.from("proveedores").select("id", { count: "exact", head: true });
    if ((provs ?? 0) === 0) await admin.from("proveedores").insert({ nombre: "Proveedor principal" });
    await auditar(r.id!, nombre, "Primer uso", `Se creó el administrador ${nombre}`);
    return responder(200, { ok: true, user_id: r.id });
  }

  // ---------- Las demás acciones: solo un administrador activo ----------
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: quien } = await admin.auth.getUser(token);
  if (!quien?.user) return error(401, "Tu sesión venció. Volvé a iniciar sesión.");
  const { data: yo } = await admin.from("miembros").select("nombre, rol, activo").eq("user_id", quien.user.id).maybeSingle();
  if (!yo || !yo.activo || yo.rol !== "admin") return error(403, "Solo el administrador puede manejar usuarios.");

  // Nunca se toca uno mismo por acá.
  const otro = async (id: unknown) => {
    if (typeof id !== "string" || id === quien.user.id) return null;
    const { data } = await admin.from("miembros").select("user_id, nombre, rol").eq("user_id", id).maybeSingle();
    return data;
  };

  switch (body.accion) {
    case "crear": {
      const nombre = limpiar(body.nombre);
      const usuario = limpiar(body.usuario).toLowerCase();
      const rol = body.rol === "admin" ? "admin" : "vendedor";
      const email = limpiar(body.email).toLowerCase();
      if (!nombreOk(nombre)) return error(400, "Escribí el nombre y apellido.");
      if (!usuarioOk(usuario)) return error(400, "El usuario solo puede tener letras, números, punto o guion (ej: juan.perez).");
      if (email && !emailOk(email)) return error(400, "Ese email no es válido.");
      if (!claveOk(body.clave)) return error(400, "La contraseña tiene que tener al menos 6 caracteres.");
      const r = await alta(nombre, usuario, body.clave, rol, email || undefined);
      if (r.error) return r.error;
      await auditar(quien.user.id, yo.nombre, "Nuevo usuario", `${nombre} (${usuario}) · ${rol === "admin" ? "Administrador" : "Vendedor"}`);
      return responder(200, { ok: true, user_id: r.id });
    }

    case "activar": {
      const u = await otro(body.user_id);
      if (!u) return error(404, "No se encontró ese usuario.");
      const activo = body.activo === true;
      // Desactivado: no puede entrar (y el servidor ya no lo deja operar aunque tenga la sesión abierta).
      const { error: e } = await admin.auth.admin.updateUserById(u.user_id, { ban_duration: activo ? "none" : "876000h" });
      if (e) return error(400, "No se pudo cambiar el estado.");
      await admin.from("miembros").update({ activo }).eq("user_id", u.user_id);
      await auditar(quien.user.id, yo.nombre, activo ? "Activó usuario" : "Desactivó usuario", u.nombre);
      return responder(200, { ok: true });
    }

    case "clave": {
      const u = await otro(body.user_id);
      if (!u) return error(404, "No se encontró ese usuario.");
      if (!claveOk(body.clave)) return error(400, "La contraseña tiene que tener al menos 6 caracteres.");
      const { error: e } = await admin.auth.admin.updateUserById(u.user_id, { password: body.clave });
      if (e) return error(400, "No se pudo cambiar la contraseña.");
      await auditar(quien.user.id, yo.nombre, "Cambió contraseña", u.nombre);
      return responder(200, { ok: true });
    }
  }
  return error(400, "Acción desconocida.");
});
