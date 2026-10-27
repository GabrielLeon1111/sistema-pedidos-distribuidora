-- =================================================================
--  FACTURACIÓN: timbrado, IVA por producto y factura en cada venta
-- =================================================================

alter table public.negocio
  add column propietario text check (char_length(propietario) <= 80),
  add column actividades text check (char_length(actividades) <= 400);

alter table public.productos add column iva smallint not null default 10 check (iva in (0, 5, 10));

create table public.timbrados (
  id uuid primary key default gen_random_uuid(),
  numero text not null check (numero ~ '^[0-9]{8}$'),
  inicio date not null,
  fin date not null,
  establecimiento text not null default '001' check (establecimiento ~ '^[0-9]{3}$'),
  punto text not null default '001' check (punto ~ '^[0-9]{3}$'),
  desde integer not null default 1,
  hasta integer not null default 9999999,
  siguiente integer not null,
  activo boolean not null default true,
  creado timestamptz not null default now(),
  check (fin >= inicio),
  check (desde >= 1 and hasta <= 9999999 and hasta >= desde),
  check (siguiente between desde and hasta + 1)
);
-- Se factura con un solo timbrado a la vez.
create unique index timbrados_un_activo on public.timbrados ((true)) where activo;
alter table public.timbrados enable row level security;
revoke all on public.timbrados from anon;
revoke insert, update, delete, truncate on public.timbrados from authenticated;
create policy "admin lee timbrados" on public.timbrados for select to authenticated using (es_admin());

alter table public.ventas
  add column timbrado_id uuid references public.timbrados(id),
  add column timbrado_numero text,
  add column timbrado_inicio date,
  add column timbrado_fin date,
  add column establecimiento text,
  add column punto text,
  add column factura_numero integer,
  add column condicion text check (condicion in ('contado', 'credito')),
  add column nota_remision text check (char_length(nota_remision) <= 30);
-- Nunca dos facturas con el mismo número.
create unique index ventas_factura_unica on public.ventas (timbrado_id, establecimiento, punto, factura_numero) where factura_numero is not null;

-- ---------------- Factura (internas) ----------------
-- Toma el próximo número del timbrado vigente (fecha de Paraguay).
create or replace function public.emitir_factura(p_venta uuid, p_remision text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_t timbrados;
  v_hoy date := (now() at time zone 'America/Asuncion')::date;
begin
  select * into v_t from timbrados
  where activo and v_hoy between inicio and fin and siguiente <= hasta
  for update;
  if not found then raise exception 'No hay un timbrado vigente para facturar. Cargalo en Más → Timbrado.'; end if;
  update timbrados set siguiente = siguiente + 1 where id = v_t.id;
  update ventas set timbrado_id = v_t.id, timbrado_numero = v_t.numero, timbrado_inicio = v_t.inicio, timbrado_fin = v_t.fin,
    establecimiento = v_t.establecimiento, punto = v_t.punto, factura_numero = v_t.siguiente, condicion = 'credito',
    nota_remision = limpiar(p_remision)
  where id = p_venta;
end $$;

-- Contado si quedó todo pagado al emitirla; si no, crédito.
create or replace function public.fijar_condicion(p_venta uuid) returns void
language sql security definer set search_path = public, pg_temp as $$
  update ventas set condicion = case when total - pagado <= 0 then 'contado' else 'credito' end
  where id = p_venta and factura_numero is not null;
$$;

-- ---------------- Panel de timbrado ----------------
create or replace function public.guardar_timbrado(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id uuid := coalesce((p->>'id')::uuid, gen_random_uuid());
  v_antes timbrados;
  v_r timbrados;
  v_num text := p->>'numero';
  v_est text := coalesce(p->>'establecimiento', '001');
  v_pto text := coalesce(p->>'punto', '001');
  v_sig integer := (p->>'siguiente')::integer;
  v_activo boolean := coalesce((p->>'activo')::boolean, true);
begin
  perform assert_admin();
  if v_num is null or v_num !~ '^[0-9]{8}$' then raise exception 'El número de timbrado tiene 8 dígitos.'; end if;
  if v_est !~ '^[0-9]{3}$' then raise exception 'El establecimiento tiene 3 dígitos (ej: 001).'; end if;
  if v_pto !~ '^[0-9]{3}$' then raise exception 'El punto de expedición tiene 3 dígitos (ej: 001).'; end if;
  if (p->>'fin')::date < (p->>'inicio')::date then raise exception 'La fecha de fin de vigencia tiene que ser después del inicio.'; end if;
  if (p->>'desde')::integer < 1 or (p->>'hasta')::integer > 9999999 or (p->>'hasta')::integer < (p->>'desde')::integer then
    raise exception 'Revisá el rango de numeración (de 1 a 9.999.999).';
  end if;
  if v_sig < (p->>'desde')::integer or v_sig > (p->>'hasta')::integer + 1 then raise exception 'El próximo número tiene que estar dentro del rango.'; end if;
  select * into v_antes from timbrados where id = v_id for update;
  if found then
    if v_sig < v_antes.siguiente then
      raise exception 'El próximo número no puede bajar: ya se emitió hasta el %.', v_antes.siguiente - 1;
    end if;
    if exists (select 1 from ventas where timbrado_id = v_id)
       and (v_antes.numero <> v_num or v_antes.establecimiento <> v_est or v_antes.punto <> v_pto) then
      raise exception 'Este timbrado ya tiene facturas emitidas: no se puede cambiar el número ni el punto de expedición.';
    end if;
  end if;
  if v_activo then update timbrados set activo = false where activo and id <> v_id; end if;
  insert into timbrados (id, numero, inicio, fin, establecimiento, punto, desde, hasta, siguiente, activo)
  values (v_id, v_num, (p->>'inicio')::date, (p->>'fin')::date, v_est, v_pto, (p->>'desde')::integer, (p->>'hasta')::integer, v_sig, v_activo)
  on conflict (id) do update set numero = excluded.numero, inicio = excluded.inicio, fin = excluded.fin,
    establecimiento = excluded.establecimiento, punto = excluded.punto, desde = excluded.desde, hasta = excluded.hasta,
    siguiente = excluded.siguiente, activo = excluded.activo
  returning * into v_r;
  perform auditar('Negocio', case when v_antes.id is null then 'Nuevo timbrado' else 'Editó timbrado' end,
    'Timbrado N° ' || v_r.numero || ' · ' || v_r.establecimiento || '-' || v_r.punto || ' · vigencia ' ||
    to_char(v_r.inicio, 'DD/MM/YYYY') || ' al ' || to_char(v_r.fin, 'DD/MM/YYYY') || ' · próxima factura ' || v_r.siguiente, true);
  return to_jsonb(v_r);
end $$;

-- ---------------- Negocio y productos (con los campos nuevos) ----------------
create or replace function public.guardar_negocio(p jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform assert_admin();
  update negocio set nombre = coalesce(limpiar(p->>'nombre'), 'Mi Negocio'), rubro = coalesce(limpiar(p->>'rubro'), 'Venta por catálogo'),
    propietario = limpiar(p->>'propietario'), actividades = limpiar_multi(p->>'actividades'),
    ruc = limpiar(p->>'ruc'), telefono = limpiar(p->>'telefono'), direccion = limpiar(p->>'direccion'), ciudad = limpiar(p->>'ciudad'),
    email = limpiar(p->>'email'), logo_base64 = nullif(p->>'logo_base64', ''), nota_pie = limpiar_multi(p->>'nota_pie')
  where id = 'negocio';
  perform auditar('Negocio', 'Datos del negocio', 'Se actualizaron los datos que salen en las notas y facturas');
end $$;

create or replace function public.guardar_producto(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_u miembros := assert_miembro();
  v_id uuid := coalesce((p->>'id')::uuid, gen_random_uuid());
  v_antes productos;
  v_nombre text := limpiar(p->>'nombre');
  v_codigo text := limpiar(p->>'codigo');
  v_pv bigint := coalesce((p->>'precio_venta')::bigint, 0);
  v_pc bigint := coalesce((p->>'precio_compra')::bigint, 0);
  v_iva smallint := coalesce((p->>'iva')::smallint, 10);
  v_r productos;
  v_cambios text;
begin
  select * into v_antes from productos where id = v_id;
  if found and v_u.rol <> 'admin' then raise exception using errcode = '42501', message = 'Tu usuario no tiene permiso para hacer esto.'; end if;
  if v_nombre is null or char_length(v_nombre) < 2 then raise exception 'Escribí el nombre del producto.'; end if;
  if v_iva not in (0, 5, 10) then raise exception 'El IVA tiene que ser 10 %%, 5 %% o exenta.'; end if;
  if exists (select 1 from productos where activo and id <> v_id and lower(nombre) = lower(v_nombre)) then
    raise exception 'Ya existe un producto con ese nombre. Buscalo en la lista.';
  end if;
  if v_codigo is not null and exists (select 1 from productos where activo and id <> v_id and lower(codigo) = lower(v_codigo)) then
    raise exception 'El código % ya es de otro producto.', v_codigo;
  end if;
  if v_u.rol <> 'admin' then v_pc := 0; end if;
  insert into productos (id, codigo, nombre, unidad, categoria, marca, proveedor_id, precio_venta, precio_compra, stock_minimo, iva, activo)
  values (v_id, v_codigo, v_nombre, coalesce(limpiar(p->>'unidad'), 'unidad'), limpiar(p->>'categoria'), limpiar(p->>'marca'),
          (p->>'proveedor_id')::uuid, v_pv, v_pc, coalesce((p->>'stock_minimo')::numeric, 0), v_iva, coalesce((p->>'activo')::boolean, true))
  on conflict (id) do update set codigo = excluded.codigo, nombre = excluded.nombre, unidad = excluded.unidad,
    categoria = excluded.categoria, marca = excluded.marca, proveedor_id = excluded.proveedor_id,
    precio_venta = excluded.precio_venta, precio_compra = excluded.precio_compra, stock_minimo = excluded.stock_minimo, iva = excluded.iva
  returning * into v_r;
  if v_antes.id is null then
    perform auditar('Inventario', 'Nuevo producto', v_nombre);
  else
    v_cambios := concat_ws(', ',
      case when v_antes.precio_venta <> v_pv then 'precio de venta ' || gs(v_antes.precio_venta) || ' → ' || gs(v_pv) end,
      case when v_antes.precio_compra <> v_pc then 'precio de compra ' || gs(v_antes.precio_compra) || ' → ' || gs(v_pc) end,
      case when v_antes.iva <> v_iva then 'IVA ' || v_antes.iva || ' % → ' || v_iva || ' %' end);
    perform auditar('Inventario', 'Editó producto', v_nombre || case when v_cambios <> '' then ': ' || v_cambios else '' end, v_cambios <> '');
  end if;
  return producto_json(v_r);
end $$;
