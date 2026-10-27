-- =================================================================
--  Las entregas y ventas directas emiten la factura. Las líneas llevan su IVA.
-- =================================================================

create or replace function public.guardar_pedido(p_id uuid, p_cliente_id uuid, p_lineas jsonb,
  p_observaciones text default null, p_fecha_entrega timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_u miembros := assert_miembro();
  v_c clientes;
  v_ant pedidos;
  v_prov uuid;
  v_l jsonb;
  v_finales jsonb := '[]';
  v_prod productos;
  v_nom text;
  v_cod text;
  v_stock boolean;
  v_iva smallint;
  v_obs text := limpiar_multi(p_observaciones);
  v_cliente jsonb;
  v_r pedidos;
begin
  select * into v_c from clientes where id = p_cliente_id;
  if not found then raise exception 'Elegí el local.'; end if;
  if jsonb_array_length(coalesce(p_lineas, '[]')) = 0 then raise exception 'Agregá al menos un producto.'; end if;
  if char_length(v_obs) > 300 then raise exception 'Las observaciones son muy largas.'; end if;
  if p_id is not null then
    select * into v_ant from pedidos where id = p_id for update;
    if not found then raise exception 'El pedido ya no existe.'; end if;
    if v_ant.estado <> 'cargado' then raise exception 'Este pedido ya se pidió al proveedor: no se puede editar.'; end if;
  end if;
  select id into v_prov from proveedores where activo order by creado limit 1;

  for v_l in select value from jsonb_array_elements(p_lineas) loop
    v_nom := limpiar(v_l->>'descripcion');
    v_cod := limpiar(v_l->>'codigo');
    v_stock := coalesce((v_l->>'de_stock')::boolean, false);
    v_iva := coalesce((v_l->>'iva')::smallint, 10);
    if v_nom is null or char_length(v_nom) < 2 then raise exception 'Hay un producto sin nombre.'; end if;
    if coalesce((v_l->>'cantidad')::numeric, 0) <= 0 or (v_l->>'cantidad')::numeric > 100000 then raise exception 'Revisá la cantidad de %.', v_nom; end if;
    if coalesce((v_l->>'precio')::bigint, -1) < 0 or (v_l->>'precio')::bigint > 999999999 then raise exception 'Revisá el precio de %.', v_nom; end if;
    if v_l->>'desc_pct' is not null and ((v_l->>'desc_pct')::numeric < 0 or (v_l->>'desc_pct')::numeric > 100) then
      raise exception 'El descuento de % tiene que ser de 0 a 100 %%.', v_nom;
    end if;
    if coalesce((v_l->>'desc_monto')::bigint, 0) < 0 then raise exception 'Revisá el descuento de %.', v_nom; end if;
    if v_iva not in (0, 5, 10) then v_iva := 10; end if;

    v_prod := null;
    if v_l->>'producto_id' is not null then
      select * into v_prod from productos where id = (v_l->>'producto_id')::uuid;
    end if;
    if v_prod.id is null then
      select * into v_prod from productos
      where (v_cod is not null and lower(codigo) = lower(v_cod)) or lower(nombre) = lower(v_nom)
      order by activo desc, creado limit 1;
    end if;
    if v_prod.id is null then
      insert into productos (codigo, nombre, unidad, proveedor_id, precio_venta, iva)
      values (v_cod, v_nom, coalesce(limpiar(v_l->>'unidad'), 'unidad'), v_prov, (v_l->>'precio')::bigint, v_iva)
      returning * into v_prod;
      perform auditar('Inventario', 'Producto recordado', v_nom || ' (desde un pedido)');
    else
      update productos set precio_venta = (v_l->>'precio')::bigint, activo = true, codigo = coalesce(codigo, v_cod)
      where id = v_prod.id returning * into v_prod;
    end if;

    v_finales := v_finales || jsonb_build_array(jsonb_build_object(
      'id', coalesce(v_l->>'id', gen_random_uuid()::text),
      'producto_id', v_prod.id, 'codigo', v_prod.codigo, 'descripcion', v_prod.nombre, 'unidad', v_prod.unidad,
      'cantidad', round((v_l->>'cantidad')::numeric, 3), 'precio', (v_l->>'precio')::bigint,
      'desc_pct', (v_l->>'desc_pct')::numeric, 'desc_monto', coalesce((v_l->>'desc_monto')::bigint, 0),
      'de_stock', v_stock, 'iva', v_prod.iva,
      'costo', case when v_stock then costo_ref(v_prod) else 0 end,
      'estado', 'pendiente', 'cantidad_final', null, 'confirmacion', null));
  end loop;

  v_cliente := jsonb_build_object('nombre', v_c.nombre, 'razon_social', v_c.razon_social, 'ruc', v_c.ruc,
    'direccion', v_c.direccion, 'telefono', v_c.telefono, 'contacto', v_c.contacto);
  if v_ant.id is null then
    insert into pedidos (cliente_id, cliente, vendedor_id, vendedor_nombre, lineas, observaciones, fecha_entrega)
    values (v_c.id, v_cliente, v_u.user_id, v_u.nombre, v_finales, v_obs, p_fecha_entrega)
    returning * into v_r;
  else
    update pedidos set cliente_id = v_c.id, cliente = v_cliente, lineas = v_finales, observaciones = v_obs,
      fecha_entrega = p_fecha_entrega, actualizado = now()
    where id = v_ant.id returning * into v_r;
  end if;
  perform auditar('Pedidos', case when v_ant.id is null then 'Nuevo pedido' else 'Editó pedido' end,
    'Pedido N° ' || nro(v_r.numero) || ' · ' || v_c.nombre || ' · ' || gs(lineas_total(v_r.lineas)));
  return pedido_json(v_r);
end $$;

create or replace function public.entregar_pedido(p_pedido uuid, p_recibido jsonb, p_pago_monto bigint,
  p_pago_metodo text, p_observaciones text, p_nota_remision text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_u miembros := assert_admin();
  v_p pedidos;
  v_l jsonb;
  v_ef numeric;
  v_q numeric;
  v_parcial boolean := false;
  v_costo bigint;
  v_prod productos;
  v_lineas jsonb := '[]';
  v_ref text;
  v_v ventas;
begin
  select * into v_p from pedidos where id = p_pedido for update;
  if not found then raise exception 'El pedido ya no existe.'; end if;
  if pedido_esperando(v_p) then raise exception 'Hay productos esperando que el local confirme si acepta la cantidad que llegó.'; end if;
  if not pedido_entregable(v_p) then
    raise exception 'Este pedido está "%": todavía no se puede entregar.', estado_pedido_texto(v_p.estado);
  end if;
  v_ref := 'Pedido N° ' || nro(v_p.numero);
  for v_l in select value from jsonb_array_elements(v_p.lineas) loop
    v_ef := linea_efectiva(v_l);
    continue when v_ef <= 0;
    v_q := coalesce((p_recibido->>(v_l->>'id'))::numeric, v_ef);
    if v_q < 0 or v_q > v_ef + 0.0001 then raise exception 'En %: puede recibir entre 0 y %.', v_l->>'descripcion', cant(v_ef); end if;
    if v_q < v_ef - 0.0001 then v_parcial := true; end if;
    v_costo := coalesce((v_l->>'costo')::bigint, 0);
    if coalesce((v_l->>'de_stock')::boolean, false) then
      if v_q > 0 then
        v_prod := mover_stock((v_l->>'producto_id')::uuid, -v_q, 'venta', 0, 'Entrega a ' || (v_p.cliente->>'nombre'), v_ref);
        v_costo := costo_ref(v_prod);
      end if;
    elsif v_q < v_ef then
      perform sobrante_al_stock(v_l, v_ef - v_q, v_ref, 'El local no recibió todo');
    end if;
    continue when v_q <= 0;
    v_lineas := v_lineas || jsonb_build_array(jsonb_build_object(
      'id', v_l->>'id', 'producto_id', v_l->'producto_id', 'codigo', v_l->'codigo', 'descripcion', v_l->>'descripcion',
      'unidad', v_l->>'unidad', 'cantidad', v_q, 'precio', (v_l->>'precio')::bigint, 'desc_pct', v_l->'desc_pct',
      'desc_monto', case when v_l->>'desc_pct' is not null or (v_l->>'cantidad')::numeric <= 0 then 0
                         else round(coalesce((v_l->>'desc_monto')::numeric, 0) * v_q / (v_l->>'cantidad')::numeric) end,
      'de_stock', coalesce((v_l->>'de_stock')::boolean, false), 'costo', v_costo, 'iva', coalesce((v_l->>'iva')::int, 10),
      'estado', 'llego', 'cantidad_final', null, 'confirmacion', null));
  end loop;
  if jsonb_array_length(v_lineas) = 0 then
    raise exception 'No hay nada para entregar. Si el local no recibió nada, marcá "No recibió el pedido".';
  end if;
  insert into ventas (cliente_id, cliente, pedido_id, pedido_numero, vendedor_nombre, lineas, observaciones, total, costo_total, entrega_parcial)
  values (v_p.cliente_id, v_p.cliente, v_p.id, v_p.numero, coalesce(v_p.vendedor_nombre, v_u.nombre), v_lineas,
          coalesce(limpiar_multi(p_observaciones), v_p.observaciones), lineas_total(v_lineas), lineas_costo(v_lineas), v_parcial)
  returning * into v_v;
  perform emitir_factura(v_v.id, p_nota_remision);
  update pedidos set estado = 'entregado', venta_id = v_v.id, actualizado = now() where id = v_p.id;
  perform auditar('Entregas', case when v_parcial then 'Entrega parcial' else 'Entrega' end,
    v_ref || ' · ' || (v_p.cliente->>'nombre') || ' · Nota de venta N° ' || nro(v_v.numero) || ' por ' || gs(v_v.total), v_parcial);
  perform cobrar_venta(v_v.id, coalesce(p_pago_monto, 0), p_pago_metodo, sena_de_pedido(v_p.id));
  perform fijar_condicion(v_v.id);
  select * into v_v from ventas where id = v_v.id;
  return to_jsonb(v_v);
end $$;

create or replace function public.venta_directa(p_cliente uuid, p_lineas jsonb, p_pago_monto bigint,
  p_pago_metodo text, p_observaciones text, p_nota_remision text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_u miembros := assert_admin();
  v_c clientes;
  v_l jsonb;
  v_prod productos;
  v_finales jsonb := '[]';
  v_numero bigint;
  v_costo bigint;
  v_v ventas;
begin
  select * into v_c from clientes where id = p_cliente;
  if not found then raise exception 'Elegí el local.'; end if;
  if jsonb_array_length(coalesce(p_lineas, '[]')) = 0 then raise exception 'Agregá al menos un producto.'; end if;
  v_numero := nextval('nro_venta');
  for v_l in select value from jsonb_array_elements(p_lineas) loop
    if v_l->>'producto_id' is null then raise exception '% no está en el inventario.', v_l->>'descripcion'; end if;
    if coalesce((v_l->>'cantidad')::numeric, 0) <= 0 then raise exception 'Revisá la cantidad de %.', v_l->>'descripcion'; end if;
    if coalesce((v_l->>'precio')::bigint, -1) < 0 then raise exception 'Revisá el precio de %.', v_l->>'descripcion'; end if;
    select * into v_prod from productos where id = (v_l->>'producto_id')::uuid;
    if not found then raise exception '% ya no está en el inventario.', v_l->>'descripcion'; end if;
    v_costo := costo_ref(v_prod);
    perform mover_stock(v_prod.id, -(v_l->>'cantidad')::numeric, 'venta', 0, 'Venta directa a ' || v_c.nombre, 'Nota de venta N° ' || nro(v_numero));
    update productos set precio_venta = (v_l->>'precio')::bigint where id = v_prod.id;
    v_finales := v_finales || jsonb_build_array(jsonb_build_object(
      'id', coalesce(v_l->>'id', gen_random_uuid()::text), 'producto_id', v_prod.id, 'codigo', v_prod.codigo,
      'descripcion', v_prod.nombre, 'unidad', v_prod.unidad, 'cantidad', round((v_l->>'cantidad')::numeric, 3),
      'precio', (v_l->>'precio')::bigint, 'desc_pct', (v_l->>'desc_pct')::numeric, 'desc_monto', coalesce((v_l->>'desc_monto')::bigint, 0),
      'de_stock', true, 'costo', v_costo, 'iva', v_prod.iva, 'estado', 'llego', 'cantidad_final', null, 'confirmacion', null));
  end loop;
  insert into ventas (numero, cliente_id, cliente, vendedor_nombre, lineas, observaciones, total, costo_total)
  values (v_numero, v_c.id, jsonb_build_object('nombre', v_c.nombre, 'razon_social', v_c.razon_social, 'ruc', v_c.ruc,
            'direccion', v_c.direccion, 'telefono', v_c.telefono, 'contacto', v_c.contacto),
          v_u.nombre, v_finales, limpiar_multi(p_observaciones), lineas_total(v_finales), lineas_costo(v_finales))
  returning * into v_v;
  perform emitir_factura(v_v.id, p_nota_remision);
  perform auditar('Entregas', 'Venta directa', 'Nota de venta N° ' || nro(v_v.numero) || ' · ' || v_c.nombre || ' · ' || gs(v_v.total));
  perform cobrar_venta(v_v.id, coalesce(p_pago_monto, 0), p_pago_metodo, 0);
  perform fijar_condicion(v_v.id);
  select * into v_v from ventas where id = v_v.id;
  return to_jsonb(v_v);
end $$;

-- Las versiones anteriores (sin nota de remisión) quedan como atajo a las nuevas:
-- así toda venta emite su factura. No se borra nada.
create or replace function public.entregar_pedido(p_pedido uuid, p_recibido jsonb default null, p_pago_monto bigint default 0,
  p_pago_metodo text default 'efectivo', p_observaciones text default null) returns jsonb
language sql security definer set search_path = public, pg_temp as $f$
  select entregar_pedido(p_pedido, p_recibido, p_pago_monto, p_pago_metodo, p_observaciones, null::text)
$f$;

create or replace function public.venta_directa(p_cliente uuid, p_lineas jsonb, p_pago_monto bigint default 0,
  p_pago_metodo text default 'efectivo', p_observaciones text default null) returns jsonb
language sql security definer set search_path = public, pg_temp as $f$
  select venta_directa(p_cliente, p_lineas, p_pago_monto, p_pago_metodo, p_observaciones, null::text)
$f$;

-- Permisos de las funciones nuevas o recreadas.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.es_miembro(), public.es_admin(),
  public.listar_productos(boolean), public.listar_pedidos(text[], uuid, timestamptz, timestamptz),
  public.obtener_pedido(uuid), public.senas_pedido(uuid), public.rechazos_cliente(uuid),
  public.guardar_cliente(jsonb), public.activar_cliente(uuid, boolean),
  public.guardar_producto(jsonb), public.activar_producto(uuid, boolean),
  public.guardar_proveedor(jsonb), public.guardar_negocio(jsonb), public.guardar_timbrado(jsonb),
  public.registrar_gasto(text, bigint, timestamptz, text, text), public.anular_gasto(uuid, text),
  public.ajustar_stock(uuid, numeric, text), public.salida_stock(uuid, numeric, text, text),
  public.registrar_compra(uuid, text, text, jsonb),
  public.guardar_pedido(uuid, uuid, jsonb, text, timestamptz), public.anular_pedido(uuid, text),
  public.confirmar_parcial(uuid, text, boolean), public.crear_consolidados(uuid[]),
  public.registrar_recepcion(uuid, jsonb), public.entregar_pedido(uuid, jsonb, bigint, text, text, text),
  public.no_estaba(uuid, timestamptz), public.rechazar_pedido(uuid, text),
  public.venta_directa(uuid, jsonb, bigint, text, text, text), public.anular_venta(uuid, text),
  public.registrar_pago(uuid, bigint, text, timestamptz, text, uuid, uuid), public.anular_pago(uuid, text)
to authenticated;
