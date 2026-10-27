-- =================================================================
--  FUNCIONES DE AYUDA (internas) Y ALTAS/BAJAS/MODIFICACIONES
--  Las de ayuda no se pueden llamar desde la app: solo las usan las
--  funciones públicas (que corren como dueño y validan permisos).
-- =================================================================

-- ---------------- Textos ----------------
-- Caracteres invisibles (espacios de ancho cero, marcas de dirección de texto).
create or replace function public.invisibles() returns text
language sql immutable as $$
  select chr(8203) || '-' || chr(8207) || chr(8232) || '-' || chr(8238) || chr(8288) || '-' || chr(8303) || chr(65279)
$$;

create or replace function public.limpiar(t text) returns text
language sql immutable as $$
  select nullif(btrim(regexp_replace(regexp_replace(coalesce(t, ''), '[[:cntrl:]' || invisibles() || ']', '', 'g'), '[[:space:]]+', ' ', 'g')), '');
$$;

-- Conserva los saltos de línea (observaciones).
create or replace function public.limpiar_multi(t text) returns text
language sql immutable as $$
  select nullif(btrim(regexp_replace(regexp_replace(regexp_replace(replace(coalesce(t, ''), chr(13), ''),
    '[' || chr(1) || '-' || chr(9) || chr(11) || '-' || chr(31) || chr(127) || invisibles() || ']', '', 'g'),
    ' +', ' ', 'g'), chr(10) || '{3,}', chr(10) || chr(10), 'g')), '');
$$;

create or replace function public.nro(n bigint) returns text language sql immutable as $$ select lpad(n::text, 6, '0') $$;
create or replace function public.gs(n numeric) returns text language sql immutable as $$
  select 'Gs. ' || replace(to_char(round(n), 'FM999,999,999,990'), ',', '.')
$$;
create or replace function public.cant(n numeric) returns text language sql immutable as $$
  select replace(trim_scale(n)::text, '.', ',')
$$;

-- ---------------- Cuentas de las líneas (iguales a lib/models/linea.dart) ----------------
create or replace function public.linea_efectiva(l jsonb) returns numeric language sql immutable as $$
  select case when l->>'estado' in ('no_llego', 'rechazada') then 0
              else coalesce((l->>'cantidad_final')::numeric, (l->>'cantidad')::numeric) end
$$;

-- Total de la línea con la cantidad q (ya con su descuento).
create or replace function public.linea_total_q(l jsonb, q numeric) returns bigint language sql immutable as $$
  with b as (select round(q * (l->>'precio')::numeric) as bruto)
  select (bruto - least(bruto, greatest(0,
           case when l->>'desc_pct' is not null then round(bruto * (l->>'desc_pct')::numeric / 100)
                when coalesce((l->>'cantidad')::numeric, 0) <= 0 then 0
                else round(coalesce((l->>'desc_monto')::numeric, 0) * q / (l->>'cantidad')::numeric) end)))::bigint
  from b
$$;

create or replace function public.linea_total(l jsonb) returns bigint language sql immutable as $$
  select linea_total_q(l, linea_efectiva(l))
$$;

create or replace function public.lineas_total(ls jsonb) returns bigint language sql immutable as $$
  select coalesce(sum(linea_total(e)), 0)::bigint from jsonb_array_elements(ls) e
$$;

create or replace function public.lineas_costo(ls jsonb) returns bigint language sql immutable as $$
  select coalesce(sum(round(linea_efectiva(e) * coalesce((e->>'costo')::numeric, 0))), 0)::bigint from jsonb_array_elements(ls) e
$$;

create or replace function public.costo_ref(p public.productos) returns bigint language sql immutable as $$
  select case when p.costo_promedio > 0 then p.costo_promedio else p.precio_compra end
$$;

-- ---------------- Historial ----------------
create or replace function public.auditar(p_area text, p_accion text, p_detalle text, p_importante boolean default false) returns void
language sql security definer set search_path = public as $$
  insert into historial (usuario_id, usuario_nombre, area, accion, detalle, importante)
  values (auth.uid(), coalesce((select nombre from miembros where user_id = auth.uid()), 'Sistema'), p_area, p_accion, coalesce(p_detalle, ''), p_importante);
$$;

-- ---------------- Stock ----------------
-- Suma o resta stock y deja el movimiento. En las entradas con costo recalcula el promedio.
create or replace function public.mover_stock(
  p_producto uuid, p_cantidad numeric, p_tipo text, p_costo bigint default 0,
  p_motivo text default null, p_referencia text default null, p_exigir boolean default true
) returns public.productos
language plpgsql security definer set search_path = public as $$
declare
  v_p productos;
  v_q numeric := round(p_cantidad, 3);
  v_nuevo numeric;
  v_prom bigint;
  v_base numeric;
  v_costo_mov bigint;
begin
  select * into v_p from productos where id = p_producto for update;
  if not found then raise exception 'El producto ya no existe.'; end if;
  if v_q = 0 then return v_p; end if;
  if v_q < 0 and p_exigir and v_p.stock + v_q < -0.0001 then
    raise exception 'No hay stock suficiente de %: hay % %.', v_p.nombre, cant(v_p.stock), v_p.unidad;
  end if;
  v_nuevo := round(v_p.stock + v_q, 3);
  v_prom := v_p.costo_promedio;
  if v_q > 0 and p_costo > 0 then
    v_base := greatest(v_p.stock, 0);
    v_prom := round((v_base * v_p.costo_promedio + v_q * p_costo) / (v_base + v_q));
  end if;
  v_costo_mov := case when p_costo > 0 then p_costo else costo_ref(v_p) end;
  update productos set stock = v_nuevo, costo_promedio = v_prom where id = v_p.id returning * into v_p;
  insert into movimientos (producto_id, producto_nombre, tipo, cantidad, costo_unitario, stock_resultante, motivo, referencia, usuario_nombre)
  values (v_p.id, v_p.nombre, p_tipo, v_q, v_costo_mov, v_nuevo, p_motivo, p_referencia,
          (select nombre from miembros where user_id = auth.uid()));
  return v_p;
end $$;

-- Mercadería de un pedido que el local no recibió: entra al stock con lo que se pagó.
create or replace function public.sobrante_al_stock(l jsonb, q numeric, p_ref text, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if q <= 0 or l->>'producto_id' is null then return; end if;
  perform mover_stock((l->>'producto_id')::uuid, q, 'sobrante_pedido', coalesce((l->>'costo')::bigint, 0), p_motivo, p_ref);
end $$;

-- ---------------- Pagos ----------------
create or replace function public.aplicado(apps jsonb) returns bigint language sql immutable as $$
  select coalesce(sum((e->>'monto')::bigint), 0)::bigint from jsonb_array_elements(apps) e
$$;

create or replace function public.agregar_aplicacion(apps jsonb, p_venta uuid, p_numero bigint, p_monto bigint) returns jsonb
language sql immutable as $$
  select case
    when exists (select 1 from jsonb_array_elements(apps) e where e->>'venta_id' = p_venta::text) then
      (select jsonb_agg(case when e->>'venta_id' = p_venta::text
                             then jsonb_set(e, '{monto}', to_jsonb((e->>'monto')::bigint + p_monto)) else e end order by o)
       from jsonb_array_elements(apps) with ordinality t(e, o))
    else apps || jsonb_build_array(jsonb_build_object('venta_id', p_venta, 'venta_numero', p_numero, 'monto', p_monto))
  end
$$;

-- Reparte lo que los pagos tienen a favor entre las notas con saldo, de la más vieja
-- a la más nueva. Una seña de un pedido abierto queda reservada; si el pedido se
-- entregó, va primero a su nota de venta.
create or replace function public.aplicar_creditos(p_cliente uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_pago pagos;
  v_venta ventas;
  v_ped pedidos;
  v_libre bigint;
  v_m bigint;
  v_apps jsonb;
  v_destino uuid;
begin
  for v_pago in select * from pagos where cliente_id = p_cliente and not anulado order by fecha, numero for update loop
    v_libre := v_pago.monto - aplicado(v_pago.aplicaciones);
    continue when v_libre <= 0;
    v_destino := null;
    if v_pago.pedido_id is not null then
      select * into v_ped from pedidos where id = v_pago.pedido_id;
      if found and v_ped.estado not in ('entregado', 'rechazado', 'anulado') then continue; end if;
      if found then v_destino := v_ped.venta_id; end if;
    end if;
    v_apps := v_pago.aplicaciones;
    for v_venta in
      select * from ventas where cliente_id = p_cliente and not anulada and total - pagado > 0
      order by (id = v_destino) desc nulls last, fecha, numero for update
    loop
      exit when v_libre <= 0;
      v_m := least(v_venta.total - v_venta.pagado, v_libre);
      update ventas set pagado = pagado + v_m where id = v_venta.id;
      v_libre := v_libre - v_m;
      v_apps := agregar_aplicacion(v_apps, v_venta.id, v_venta.numero, v_m);
    end loop;
    update pagos set aplicaciones = v_apps where id = v_pago.id;
  end loop;
end $$;

-- Saca de los pagos lo aplicado a esta nota (al anularla).
create or replace function public.desaplicar_venta(p_venta uuid) returns void
language sql security definer set search_path = public as $$
  update pagos set aplicaciones = coalesce(
    (select jsonb_agg(e) from jsonb_array_elements(aplicaciones) e where e->>'venta_id' <> p_venta::text), '[]')
  where aplicaciones @> jsonb_build_array(jsonb_build_object('venta_id', p_venta));
$$;

-- Recalcula lo pagado de cada nota a partir de las aplicaciones.
create or replace function public.recalcular_pagado(p_cliente uuid) returns void
language sql security definer set search_path = public as $$
  update ventas v set pagado = coalesce((
    select sum((e->>'monto')::bigint) from pagos p, jsonb_array_elements(p.aplicaciones) e
    where p.cliente_id = p_cliente and not p.anulado and e->>'venta_id' = v.id::text), 0)
  where v.cliente_id = p_cliente and not v.anulada;
$$;

-- Lo que hay de seña (sin aplicar) para un pedido.
create or replace function public.sena_de_pedido(p_pedido uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(sum(monto - aplicado(aplicaciones)), 0)::bigint from pagos where pedido_id = p_pedido and not anulado
$$;

-- ---------------- Lo que ve cada uno ----------------
-- El vendedor no ve costos.
create or replace function public.pedido_json(p public.pedidos) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when es_admin() then to_jsonb(p)
    else jsonb_set(to_jsonb(p), '{lineas}', coalesce((select jsonb_agg(e - 'costo' order by o) from jsonb_array_elements(p.lineas) with ordinality t(e, o)), '[]'))
  end
$$;

create or replace function public.producto_json(p public.productos) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when es_admin() then to_jsonb(p) else to_jsonb(p) - 'precio_compra' - 'costo_promedio' end
$$;

create or replace function public.listar_productos(p_incluir_inactivos boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_miembro();
  return coalesce((select jsonb_agg(producto_json(p) order by lower(p.nombre)) from productos p where p_incluir_inactivos or p.activo), '[]');
end $$;

create or replace function public.listar_pedidos(
  p_estados text[] default null, p_cliente uuid default null, p_desde timestamptz default null, p_hasta timestamptz default null
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_miembro();
  return coalesce((
    select jsonb_agg(pedido_json(p) order by p.numero desc) from pedidos p
    where (p_estados is null or p.estado = any(p_estados))
      and (p_cliente is null or p.cliente_id = p_cliente)
      and (p_desde is null or p.fecha >= p_desde)
      and (p_hasta is null or p.fecha <= p_hasta)), '[]');
end $$;

create or replace function public.obtener_pedido(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v pedidos;
begin
  perform assert_miembro();
  select * into v from pedidos where id = p_id;
  if not found then raise exception 'El pedido ya no existe.'; end if;
  return pedido_json(v);
end $$;

-- Señas del pedido (para mostrarlas en la nota, también al vendedor).
create or replace function public.senas_pedido(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_miembro();
  return coalesce((select jsonb_agg(to_jsonb(p) order by p.fecha) from pagos p where p.pedido_id = p_id and not p.anulado), '[]');
end $$;

-- Historial de rechazos del local (se avisa al cargarle un pedido nuevo).
create or replace function public.rechazos_cliente(p_cliente uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_miembro();
  return coalesce((
    select jsonb_agg(r order by r->>'fecha' desc) from (
      select jsonb_build_object('fecha', p.actualizado, 'pedido_numero', p.numero,
               'detalle', 'No recibió el pedido' || coalesce(': ' || p.motivo, ''), 'monto', lineas_total(p.lineas)) r
      from pedidos p where p.cliente_id = p_cliente and p.estado = 'rechazado'
      union all
      select jsonb_build_object('fecha', p.actualizado, 'pedido_numero', p.numero,
               'detalle', 'No aceptó la parte que llegó de ' || (e->>'descripcion'), 'monto', linea_total_q(e, (e->>'cantidad')::numeric))
      from pedidos p, jsonb_array_elements(p.lineas) e where p.cliente_id = p_cliente and e->>'estado' = 'rechazada'
      union all
      select jsonb_build_object('fecha', v.fecha, 'pedido_numero', coalesce(v.pedido_numero, 0),
               'detalle', 'Recibió solo una parte (nota de venta N° ' || nro(v.numero) || ')', 'monto', 0)
      from ventas v where v.cliente_id = p_cliente and v.entrega_parcial
    ) x), '[]');
end $$;

-- ---------------- Clientes ----------------
create or replace function public.guardar_cliente(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := coalesce((p->>'id')::uuid, gen_random_uuid());
  v_nombre text := limpiar(p->>'nombre');
  v_existe boolean;
  v_c clientes;
begin
  perform assert_miembro();
  if v_nombre is null or char_length(v_nombre) < 2 then raise exception 'Escribí el nombre del local.'; end if;
  if exists (select 1 from clientes where lower(nombre) = lower(v_nombre) and id <> v_id) then
    raise exception 'Ya existe un local con ese nombre. Buscalo en la lista.';
  end if;
  v_existe := exists (select 1 from clientes where id = v_id);
  insert into clientes (id, nombre, razon_social, ruc, direccion, telefono, contacto, notas, activo)
  values (v_id, v_nombre, limpiar(p->>'razon_social'), limpiar(p->>'ruc'), limpiar(p->>'direccion'), limpiar(p->>'telefono'),
          limpiar(p->>'contacto'), limpiar_multi(p->>'notas'), coalesce((p->>'activo')::boolean, true))
  on conflict (id) do update set nombre = excluded.nombre, razon_social = excluded.razon_social, ruc = excluded.ruc,
    direccion = excluded.direccion, telefono = excluded.telefono, contacto = excluded.contacto, notas = excluded.notas
  returning * into v_c;
  perform auditar('Clientes', case when v_existe then 'Editó local' else 'Nuevo local' end, v_nombre);
  return to_jsonb(v_c);
end $$;

create or replace function public.activar_cliente(p_id uuid, p_activo boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_n text;
begin
  perform assert_admin();
  update clientes set activo = p_activo where id = p_id returning nombre into v_n;
  if v_n is null then raise exception 'El local ya no existe.'; end if;
  perform auditar('Clientes', case when p_activo then 'Reactivó local' else 'Desactivó local' end, v_n);
end $$;

-- ---------------- Productos ----------------
create or replace function public.guardar_producto(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_u miembros := assert_miembro();
  v_id uuid := coalesce((p->>'id')::uuid, gen_random_uuid());
  v_antes productos;
  v_nombre text := limpiar(p->>'nombre');
  v_codigo text := limpiar(p->>'codigo');
  v_pv bigint := coalesce((p->>'precio_venta')::bigint, 0);
  v_pc bigint := coalesce((p->>'precio_compra')::bigint, 0);
  v_r productos;
  v_cambios text;
begin
  select * into v_antes from productos where id = v_id;
  if found and v_u.rol <> 'admin' then raise exception using errcode = '42501', message = 'Tu usuario no tiene permiso para hacer esto.'; end if;
  if v_nombre is null or char_length(v_nombre) < 2 then raise exception 'Escribí el nombre del producto.'; end if;
  if exists (select 1 from productos where activo and id <> v_id and lower(nombre) = lower(v_nombre)) then
    raise exception 'Ya existe un producto con ese nombre. Buscalo en la lista.';
  end if;
  if v_codigo is not null and exists (select 1 from productos where activo and id <> v_id and lower(codigo) = lower(v_codigo)) then
    raise exception 'El código % ya es de otro producto.', v_codigo;
  end if;
  if v_u.rol <> 'admin' then v_pc := 0; end if;
  insert into productos (id, codigo, nombre, unidad, categoria, marca, proveedor_id, precio_venta, precio_compra, stock_minimo, activo)
  values (v_id, v_codigo, v_nombre, coalesce(limpiar(p->>'unidad'), 'unidad'), limpiar(p->>'categoria'), limpiar(p->>'marca'),
          (p->>'proveedor_id')::uuid, v_pv, v_pc, coalesce((p->>'stock_minimo')::numeric, 0), coalesce((p->>'activo')::boolean, true))
  on conflict (id) do update set codigo = excluded.codigo, nombre = excluded.nombre, unidad = excluded.unidad,
    categoria = excluded.categoria, marca = excluded.marca, proveedor_id = excluded.proveedor_id,
    precio_venta = excluded.precio_venta, precio_compra = excluded.precio_compra, stock_minimo = excluded.stock_minimo
  returning * into v_r;
  if v_antes.id is null then
    perform auditar('Inventario', 'Nuevo producto', v_nombre);
  else
    v_cambios := concat_ws(', ',
      case when v_antes.precio_venta <> v_pv then 'precio de venta ' || gs(v_antes.precio_venta) || ' → ' || gs(v_pv) end,
      case when v_antes.precio_compra <> v_pc then 'precio de compra ' || gs(v_antes.precio_compra) || ' → ' || gs(v_pc) end);
    perform auditar('Inventario', 'Editó producto', v_nombre || case when v_cambios <> '' then ': ' || v_cambios else '' end, v_cambios <> '');
  end if;
  return producto_json(v_r);
end $$;

create or replace function public.activar_producto(p_id uuid, p_activo boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_n text;
begin
  perform assert_admin();
  update productos set activo = p_activo where id = p_id returning nombre into v_n;
  if v_n is null then raise exception 'El producto ya no existe.'; end if;
  perform auditar('Inventario', case when p_activo then 'Reactivó producto' else 'Desactivó producto' end, v_n);
end $$;

-- ---------------- Proveedores ----------------
create or replace function public.guardar_proveedor(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := coalesce((p->>'id')::uuid, gen_random_uuid());
  v_nombre text := limpiar(p->>'nombre');
  v_existe boolean;
  v_r proveedores;
begin
  perform assert_admin();
  if v_nombre is null or char_length(v_nombre) < 2 then raise exception 'Escribí el nombre del proveedor.'; end if;
  v_existe := exists (select 1 from proveedores where id = v_id);
  insert into proveedores (id, nombre, telefono, notas, activo)
  values (v_id, v_nombre, limpiar(p->>'telefono'), limpiar_multi(p->>'notas'), coalesce((p->>'activo')::boolean, true))
  on conflict (id) do update set nombre = excluded.nombre, telefono = excluded.telefono, notas = excluded.notas, activo = excluded.activo
  returning * into v_r;
  perform auditar('Proveedor', case when v_existe then 'Editó proveedor' else 'Nuevo proveedor' end, v_nombre);
  return to_jsonb(v_r);
end $$;

-- ---------------- Negocio ----------------
create or replace function public.guardar_negocio(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_admin();
  update negocio set nombre = coalesce(limpiar(p->>'nombre'), 'Mi Negocio'), rubro = coalesce(limpiar(p->>'rubro'), 'Venta por catálogo'),
    ruc = limpiar(p->>'ruc'), telefono = limpiar(p->>'telefono'), direccion = limpiar(p->>'direccion'), ciudad = limpiar(p->>'ciudad'),
    email = limpiar(p->>'email'), logo_base64 = nullif(p->>'logo_base64', ''), nota_pie = limpiar_multi(p->>'nota_pie')
  where id = 'negocio';
  perform auditar('Negocio', 'Datos del negocio', 'Se actualizaron los datos que salen en las notas');
end $$;

-- ---------------- Gastos ----------------
create or replace function public.registrar_gasto(p_categoria text, p_monto bigint, p_fecha timestamptz default null,
  p_descripcion text default null, p_factura text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_u miembros := assert_admin(); v_g gastos;
begin
  if limpiar(p_categoria) is null then raise exception 'Elegí la categoría.'; end if;
  if p_monto is null or p_monto <= 0 or p_monto > 999999999 then raise exception 'Revisá el monto.'; end if;
  if p_fecha > now() + interval '5 minutes' then raise exception 'La fecha no puede ser futura.'; end if;
  insert into gastos (fecha, categoria, monto, descripcion, factura, registrado_por)
  values (coalesce(p_fecha, now()), limpiar(p_categoria), p_monto, limpiar(p_descripcion), limpiar(p_factura), v_u.nombre)
  returning * into v_g;
  perform auditar('Gastos', 'Gasto', v_g.categoria || ' · ' || gs(v_g.monto) || coalesce(' · ' || v_g.descripcion, ''));
  return to_jsonb(v_g);
end $$;

create or replace function public.anular_gasto(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare v_g gastos; v_m text := limpiar(p_motivo);
begin
  perform assert_admin();
  if v_m is null or char_length(v_m) < 3 then raise exception 'Escribí el motivo.'; end if;
  select * into v_g from gastos where id = p_id for update;
  if not found then raise exception 'El gasto ya no existe.'; end if;
  if v_g.anulado then raise exception 'Este gasto ya está anulado.'; end if;
  update gastos set anulado = true, motivo_anulacion = v_m where id = p_id;
  perform auditar('Gastos', 'Anuló gasto', v_g.categoria || ' · ' || gs(v_g.monto) || ' · Motivo: ' || v_m, true);
end $$;

-- ---------------- Inventario ----------------
create or replace function public.ajustar_stock(p_producto uuid, p_nuevo numeric, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare v_p productos; v_m text := limpiar(p_motivo);
begin
  perform assert_admin();
  if v_m is null or char_length(v_m) < 3 then raise exception 'Escribí el motivo.'; end if;
  if p_nuevo < 0 or p_nuevo > 100000 then raise exception 'Revisá la cantidad.'; end if;
  select * into v_p from productos where id = p_producto;
  if not found then raise exception 'El producto ya no existe.'; end if;
  if abs(p_nuevo - v_p.stock) < 0.0001 then raise exception 'El stock ya es ese.'; end if;
  perform mover_stock(p_producto, p_nuevo - v_p.stock, 'ajuste', 0, v_m, null, false);
  perform auditar('Inventario', 'Ajuste de stock', v_p.nombre || ': ' || cant(v_p.stock) || ' → ' || cant(p_nuevo) || ' · ' || v_m, true);
end $$;

-- Pérdida o devolución al proveedor.
create or replace function public.salida_stock(p_producto uuid, p_cantidad numeric, p_motivo text, p_tipo text) returns void
language plpgsql security definer set search_path = public as $$
declare v_p productos; v_m text := limpiar(p_motivo);
begin
  perform assert_admin();
  if p_tipo not in ('perdida', 'devolucion_proveedor') then raise exception 'Tipo de salida no válido.'; end if;
  if v_m is null or char_length(v_m) < 3 then raise exception 'Escribí el motivo.'; end if;
  if p_cantidad <= 0 or p_cantidad > 100000 then raise exception 'Revisá la cantidad.'; end if;
  select * into v_p from productos where id = p_producto;
  if not found then raise exception 'El producto ya no existe.'; end if;
  perform mover_stock(p_producto, -p_cantidad, p_tipo, 0, v_m);
  perform auditar('Inventario', case when p_tipo = 'perdida' then 'Pérdida' else 'Devolución al proveedor' end,
    v_p.nombre || ': ' || cant(p_cantidad) || ' ' || v_p.unidad || ' · ' || gs(p_cantidad * costo_ref(v_p)) || ' · ' || v_m, true);
end $$;

-- Compra propia para tener mercadería.
create or replace function public.registrar_compra(p_proveedor_id uuid, p_proveedor_nombre text, p_factura text, p_lineas jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_u miembros := assert_admin();
  v_c compras;
  v_l jsonb;
  v_prov text;
begin
  if jsonb_array_length(coalesce(p_lineas, '[]')) = 0 then raise exception 'Agregá al menos un producto.'; end if;
  for v_l in select * from jsonb_array_elements(p_lineas) loop
    if (v_l->>'cantidad')::numeric <= 0 or (v_l->>'cantidad')::numeric > 100000 then raise exception 'Revisá la cantidad de %.', v_l->>'descripcion'; end if;
    if (v_l->>'costo')::bigint <= 0 or (v_l->>'costo')::bigint > 999999999 then raise exception 'Poné el precio de compra de %.', v_l->>'descripcion'; end if;
  end loop;
  select nombre into v_prov from proveedores where id = p_proveedor_id;
  insert into compras (proveedor_id, proveedor_nombre, factura, lineas, registrado_por)
  values (p_proveedor_id, coalesce(v_prov, limpiar(p_proveedor_nombre), 'Sin proveedor'), limpiar(p_factura), p_lineas, v_u.nombre)
  returning * into v_c;
  for v_l in select * from jsonb_array_elements(p_lineas) loop
    perform mover_stock((v_l->>'producto_id')::uuid, (v_l->>'cantidad')::numeric, 'compra', (v_l->>'costo')::bigint, null, 'Compra N° ' || nro(v_c.numero));
    update productos set precio_compra = (v_l->>'costo')::bigint where id = (v_l->>'producto_id')::uuid;
  end loop;
  perform auditar('Inventario', 'Compra', 'N° ' || nro(v_c.numero) || ' · ' || v_c.proveedor_nombre || ' · ' ||
    gs((select sum(round((e->>'cantidad')::numeric * (e->>'costo')::numeric)) from jsonb_array_elements(p_lineas) e)));
  return to_jsonb(v_c);
end $$;
