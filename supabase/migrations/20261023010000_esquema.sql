-- =================================================================
--  SISTEMA DE PEDIDOS Y COBROS · ESQUEMA
--  Tablas con los mismos nombres de columnas que los modelos de la app.
--  Las líneas de cada documento (pedido, venta, consolidado) van en jsonb:
--  son una foto del documento y solo las escriben las funciones del servidor.
--  Seguridad:
--   - RLS en todas las tablas. Nadie escribe directo: todo pasa por funciones
--     SECURITY DEFINER que validan permisos (assert_miembro / assert_admin).
--   - El vendedor no lee costos: los pedidos y productos le llegan por
--     funciones que sacan los costos.
--   - El historial solo se agrega: no se puede editar ni borrar.
-- =================================================================

create extension if not exists pgcrypto;

-- ---------------- Usuarios de la app ----------------
create table public.miembros (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null check (char_length(nombre) between 3 and 80),
  usuario text not null unique check (usuario ~ '^[a-z0-9._-]{3,30}$'),
  rol text not null default 'vendedor' check (rol in ('admin', 'vendedor')),
  activo boolean not null default true,
  creado timestamptz not null default now()
);

-- ---------------- Datos del negocio ----------------
create table public.negocio (
  id text primary key default 'negocio' check (id = 'negocio'),
  nombre text not null default 'Mi Negocio' check (char_length(nombre) between 2 and 80),
  rubro text not null default 'Venta por catálogo' check (char_length(rubro) <= 60),
  ruc text check (char_length(ruc) <= 15),
  telefono text check (char_length(telefono) <= 20),
  direccion text check (char_length(direccion) <= 150),
  ciudad text check (char_length(ciudad) <= 60),
  email text check (char_length(email) <= 100),
  logo_base64 text check (char_length(logo_base64) <= 700000),
  nota_pie text check (char_length(nota_pie) <= 300)
);
insert into public.negocio (id) values ('negocio');

-- ---------------- Clientes (locales) ----------------
create table public.clientes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(nombre) between 2 and 80),
  razon_social text check (char_length(razon_social) <= 80),
  ruc text check (char_length(ruc) <= 15),
  direccion text check (char_length(direccion) <= 150),
  telefono text check (char_length(telefono) <= 20),
  contacto text check (char_length(contacto) <= 80),
  notas text check (char_length(notas) <= 300),
  activo boolean not null default true,
  creado timestamptz not null default now()
);
create unique index clientes_nombre_unico on public.clientes (lower(nombre));

-- ---------------- Proveedores ----------------
create table public.proveedores (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(nombre) between 2 and 80),
  telefono text check (char_length(telefono) <= 20),
  notas text check (char_length(notas) <= 300),
  activo boolean not null default true,
  creado timestamptz not null default now()
);

-- ---------------- Productos ----------------
create table public.productos (
  id uuid primary key default gen_random_uuid(),
  codigo text check (char_length(codigo) <= 30),
  nombre text not null check (char_length(nombre) between 2 and 120),
  unidad text not null default 'unidad' check (char_length(unidad) between 1 and 20),
  categoria text check (char_length(categoria) <= 40),
  marca text check (char_length(marca) <= 40),
  proveedor_id uuid references public.proveedores(id),
  precio_venta bigint not null default 0 check (precio_venta between 0 and 999999999),
  precio_compra bigint not null default 0 check (precio_compra between 0 and 999999999),
  stock numeric(14,3) not null default 0,
  costo_promedio bigint not null default 0 check (costo_promedio >= 0),
  stock_minimo numeric(14,3) not null default 0 check (stock_minimo >= 0),
  activo boolean not null default true,
  creado timestamptz not null default now()
);
create unique index productos_nombre_unico on public.productos (lower(nombre)) where activo;
create unique index productos_codigo_unico on public.productos (lower(codigo)) where activo and codigo is not null;

-- ---------------- Numeración de documentos ----------------
create sequence public.nro_pedido;
create sequence public.nro_venta;
create sequence public.nro_consolidado;
create sequence public.nro_recibo;
create sequence public.nro_compra;

-- ---------------- Notas de pedido ----------------
create table public.pedidos (
  id uuid primary key default gen_random_uuid(),
  numero bigint not null unique default nextval('public.nro_pedido'),
  fecha timestamptz not null default now(),
  cliente_id uuid not null references public.clientes(id),
  cliente jsonb not null,
  vendedor_id uuid references auth.users(id) on delete set null,
  vendedor_nombre text,
  lineas jsonb not null check (jsonb_typeof(lineas) = 'array'),
  observaciones text check (char_length(observaciones) <= 300),
  estado text not null default 'cargado'
    check (estado in ('cargado', 'pedido', 'recibido', 'pendiente', 'entregado', 'rechazado', 'anulado')),
  fecha_entrega timestamptz,
  consolidado_id uuid,
  venta_id uuid,
  motivo text check (char_length(motivo) <= 150),
  actualizado timestamptz not null default now()
);
create index pedidos_cliente on public.pedidos (cliente_id);
create index pedidos_estado on public.pedidos (estado);

-- ---------------- Consolidados (hoja para el proveedor + recepción) ----------------
create table public.consolidados (
  id uuid primary key default gen_random_uuid(),
  numero bigint not null unique default nextval('public.nro_consolidado'),
  fecha timestamptz not null default now(),
  proveedor_id uuid not null references public.proveedores(id),
  proveedor_nombre text not null,
  proveedor_telefono text,
  pedido_ids uuid[] not null,
  lineas jsonb not null check (jsonb_typeof(lineas) = 'array'),
  estado text not null default 'enviado' check (estado in ('enviado', 'recibido')),
  fecha_recepcion timestamptz,
  recibido_por text,
  creado_por text
);

-- ---------------- Notas de venta ----------------
create table public.ventas (
  id uuid primary key default gen_random_uuid(),
  numero bigint not null unique default nextval('public.nro_venta'),
  fecha timestamptz not null default now(),
  cliente_id uuid not null references public.clientes(id),
  cliente jsonb not null,
  pedido_id uuid references public.pedidos(id),
  pedido_numero bigint,
  vendedor_nombre text,
  lineas jsonb not null check (jsonb_typeof(lineas) = 'array'),
  observaciones text check (char_length(observaciones) <= 300),
  total bigint not null check (total >= 0),
  costo_total bigint not null default 0,
  pagado bigint not null default 0 check (pagado >= 0),
  entrega_parcial boolean not null default false,
  anulada boolean not null default false,
  motivo_anulacion text check (char_length(motivo_anulacion) <= 150),
  check (anulada or pagado <= total)
);
create index ventas_cliente on public.ventas (cliente_id);
create index ventas_fecha on public.ventas (fecha);

-- ---------------- Pagos (recibos) ----------------
create table public.pagos (
  id uuid primary key default gen_random_uuid(),
  numero bigint not null unique default nextval('public.nro_recibo'),
  fecha timestamptz not null default now(),
  cliente_id uuid not null references public.clientes(id),
  cliente_nombre text not null,
  monto bigint not null check (monto between 1 and 999999999),
  metodo text not null check (metodo in ('efectivo', 'transferencia', 'qr')),
  nota text check (char_length(nota) <= 150),
  pedido_id uuid references public.pedidos(id),
  pedido_numero bigint,
  aplicaciones jsonb not null default '[]' check (jsonb_typeof(aplicaciones) = 'array'),
  registrado_por text,
  anulado boolean not null default false,
  motivo_anulacion text check (char_length(motivo_anulacion) <= 150)
);
create index pagos_cliente on public.pagos (cliente_id);

-- ---------------- Movimientos de stock ----------------
create table public.movimientos (
  id uuid primary key default gen_random_uuid(),
  fecha timestamptz not null default now(),
  producto_id uuid not null references public.productos(id),
  producto_nombre text not null,
  tipo text not null check (tipo in ('sobrante_pedido', 'compra', 'venta', 'devolucion_proveedor', 'perdida', 'ajuste', 'anulacion')),
  cantidad numeric(14,3) not null,
  costo_unitario bigint not null default 0,
  stock_resultante numeric(14,3) not null,
  motivo text,
  referencia text,
  usuario_nombre text
);
create index movimientos_producto on public.movimientos (producto_id);

-- ---------------- Compras propias ----------------
create table public.compras (
  id uuid primary key default gen_random_uuid(),
  numero bigint not null unique default nextval('public.nro_compra'),
  fecha timestamptz not null default now(),
  proveedor_id uuid references public.proveedores(id),
  proveedor_nombre text not null,
  factura text check (char_length(factura) <= 30),
  lineas jsonb not null check (jsonb_typeof(lineas) = 'array'),
  registrado_por text
);

-- ---------------- Gastos ----------------
create table public.gastos (
  id uuid primary key default gen_random_uuid(),
  fecha timestamptz not null default now(),
  categoria text not null check (char_length(categoria) between 2 and 40),
  monto bigint not null check (monto between 1 and 999999999),
  descripcion text check (char_length(descripcion) <= 120),
  factura text check (char_length(factura) <= 30),
  registrado_por text,
  anulado boolean not null default false,
  motivo_anulacion text check (char_length(motivo_anulacion) <= 150)
);

-- ---------------- Historial de cambios ----------------
create table public.historial (
  id uuid primary key default gen_random_uuid(),
  fecha timestamptz not null default now(),
  usuario_id uuid,
  usuario_nombre text not null,
  area text not null,
  accion text not null,
  detalle text not null default '',
  importante boolean not null default false
);
create index historial_fecha on public.historial (fecha desc);

-- =================================================================
--  PERMISOS
-- =================================================================

create or replace function public.es_miembro() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros where user_id = auth.uid() and activo);
$$;

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros where user_id = auth.uid() and activo and rol = 'admin');
$$;

/** El usuario que llama (activo). Corta si no lo es. */
create or replace function public.assert_miembro() returns public.miembros
language plpgsql stable security definer set search_path = public as $$
declare v miembros;
begin
  select * into v from miembros where user_id = auth.uid() and activo;
  if not found then
    raise exception using errcode = '42501', message = 'Tu usuario no está habilitado. Hablá con el administrador.';
  end if;
  return v;
end $$;

create or replace function public.assert_admin() returns public.miembros
language plpgsql stable security definer set search_path = public as $$
declare v miembros;
begin
  v := assert_miembro();
  if v.rol <> 'admin' then
    raise exception using errcode = '42501', message = 'Tu usuario no tiene permiso para hacer esto.';
  end if;
  return v;
end $$;

alter table public.miembros enable row level security;
alter table public.negocio enable row level security;
alter table public.clientes enable row level security;
alter table public.proveedores enable row level security;
alter table public.productos enable row level security;
alter table public.pedidos enable row level security;
alter table public.consolidados enable row level security;
alter table public.ventas enable row level security;
alter table public.pagos enable row level security;
alter table public.movimientos enable row level security;
alter table public.compras enable row level security;
alter table public.gastos enable row level security;
alter table public.historial enable row level security;

-- Nadie anónimo ve nada.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon, authenticated;
-- Los usuarios con sesión solo leen (según las políticas); escriben las funciones.
revoke insert, update, delete, truncate on all tables in schema public from authenticated;

create policy "miembro ve su fila y el admin ve todas" on public.miembros
  for select to authenticated using (user_id = auth.uid() or es_admin());
create policy "miembros leen el negocio" on public.negocio for select to authenticated using (es_miembro());
create policy "miembros leen clientes" on public.clientes for select to authenticated using (es_miembro());
create policy "miembros leen proveedores" on public.proveedores for select to authenticated using (es_miembro());
-- Con costos: solo el administrador. El vendedor usa listar_productos().
create policy "admin lee productos" on public.productos for select to authenticated using (es_admin());
create policy "admin lee pedidos" on public.pedidos for select to authenticated using (es_admin());
create policy "admin lee consolidados" on public.consolidados for select to authenticated using (es_admin());
create policy "admin lee ventas" on public.ventas for select to authenticated using (es_admin());
create policy "admin lee pagos" on public.pagos for select to authenticated using (es_admin());
create policy "admin lee movimientos" on public.movimientos for select to authenticated using (es_admin());
create policy "admin lee compras" on public.compras for select to authenticated using (es_admin());
create policy "admin lee gastos" on public.gastos for select to authenticated using (es_admin());
create policy "admin lee historial" on public.historial for select to authenticated using (es_admin());
