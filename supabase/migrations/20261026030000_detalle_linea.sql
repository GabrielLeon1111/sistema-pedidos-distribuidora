-- =================================================================
--  DETALLE POR PRODUCTO EN LA NOTA DE PEDIDO
--  Cada línea puede llevar un detalle libre (ej. tinte: "1 rubio, 2 negros";
--  zapatillas: "2 del 38, 1 del 40"). Sale en la nota de pedido, en la hoja
--  del proveedor (junto y por local) y pasa a la nota de venta.
-- =================================================================

create or replace function public.guardar_pedido_sin_clave(p_id uuid, p_cliente_id uuid, p_lineas jsonb,
  p_observaciones text, p_fecha_entrega timestamptz, p_numero bigint, p_fecha timestamptz) returns jsonb
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
  v_fecha timestamptz;
  v_numero bigint;
  v_forma text;
  v_pres jsonb;
  v_factor numeric;
  v_nota text;
begin
  select * into v_c from clientes where id = p_cliente_id;
  if not found then raise exception 'Elegí el local.'; end if;
  if jsonb_array_length(coalesce(p_lineas, '[]')) = 0 then raise exception 'Agregá al menos un producto.'; end if;
  if char_length(v_obs) > 300 then raise exception 'Las observaciones son muy largas.'; end if;
  if p_id is not null then
    select * into v_ant from pedidos where id = p_id for update;
    if found and v_ant.estado <> 'cargado' then raise exception 'Este pedido ya se pidió al proveedor: no se puede editar.'; end if;
  end if;
  if v_ant.id is null then
    -- Pedido nuevo: número del bloque de quien lo levantó (o uno nuevo).
    if p_numero is not null then
      if not exists (select 1 from bloques_numeros where user_id = v_u.user_id and p_numero between desde and hasta) then
        raise exception 'El número de pedido % no es de tu usuario. Volvé a abrir la app con señal.', p_numero;
      end if;
      if exists (select 1 from pedidos where numero = p_numero) then
        raise exception 'El número de pedido % ya se usó en otro pedido.', p_numero;
      end if;
      v_numero := p_numero;
    else
      v_numero := tomar_numeros_pedido(1);
    end if;
    -- Fecha en que se levantó (sin señal puede ser de antes); nunca futura.
    v_fecha := least(coalesce(p_fecha, now()), now());
    if v_fecha < now() - interval '60 days' then v_fecha := now(); end if;
  end if;
  select id into v_prov from proveedores where activo order by creado limit 1;

  for v_l in select value from jsonb_array_elements(p_lineas) loop
    v_nom := limpiar(v_l->>'descripcion');
    v_cod := limpiar(v_l->>'codigo');
    v_forma := lower(limpiar(v_l->>'unidad'));
    v_nota := limpiar(v_l->>'nota');
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
    if char_length(v_nota) > 150 then raise exception 'El detalle de % es muy largo.', v_nom; end if;

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
      values (v_cod, v_nom, coalesce(v_forma, 'unidad'), v_prov, (v_l->>'precio')::bigint, v_iva)
      returning * into v_prod;
      perform auditar('Inventario', 'Producto recordado', v_nom || ' (desde un pedido)');
    else
      update productos set activo = true, codigo = coalesce(codigo, v_cod) where id = v_prod.id returning * into v_prod;
    end if;
    -- En qué forma se vende (unidad, docena, paquete...). La cantidad de
    -- unidades de cada forma la pone la base, no la app.
    v_pres := presentacion(v_prod, v_forma);
    if v_pres is null then raise exception '% no se vende por %. Elegí otra forma de venta.', v_prod.nombre, v_forma; end if;
    v_factor := (v_pres->>'unidades')::numeric;
    perform fijar_precio_venta(v_prod.id, v_pres->>'nombre', (v_l->>'precio')::bigint);

    v_finales := v_finales || jsonb_build_array(jsonb_build_object(
      'id', coalesce(v_l->>'id', gen_random_uuid()::text),
      'producto_id', v_prod.id, 'codigo', v_prod.codigo, 'descripcion', v_prod.nombre,
      'unidad', v_pres->>'nombre', 'factor', v_factor, 'nota', v_nota,
      'cantidad', round((v_l->>'cantidad')::numeric, 3), 'precio', (v_l->>'precio')::bigint,
      'desc_pct', (v_l->>'desc_pct')::numeric, 'desc_monto', coalesce((v_l->>'desc_monto')::bigint, 0),
      'de_stock', v_stock, 'iva', v_prod.iva,
      'costo', case when v_stock then round(costo_ref(v_prod) * v_factor) else 0 end,
      'estado', 'pendiente', 'cantidad_final', null, 'confirmacion', null));
  end loop;

  v_cliente := jsonb_build_object('nombre', v_c.nombre, 'razon_social', v_c.razon_social, 'ruc', v_c.ruc,
    'direccion', v_c.direccion, 'telefono', v_c.telefono, 'contacto', v_c.contacto);
  if v_ant.id is null then
    insert into pedidos (id, numero, fecha, cliente_id, cliente, vendedor_id, vendedor_nombre, lineas, observaciones, fecha_entrega)
    values (coalesce(p_id, gen_random_uuid()), v_numero, v_fecha, v_c.id, v_cliente, v_u.user_id, v_u.nombre, v_finales, v_obs, p_fecha_entrega)
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

create or replace function public.crear_consolidados_sin_clave(p_pedido_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_u miembros := assert_admin();
  v_p pedidos;
  v_def uuid;
  v_prov record;
  v_lineas jsonb;
  v_ids uuid[];
  v_c consolidados;
  v_creados uuid[] := '{}';
  v_res jsonb := '[]';
begin
  if coalesce(cardinality(p_pedido_ids), 0) = 0 then raise exception 'Elegí al menos un pedido.'; end if;
  if (select count(*) from pedidos where id = any(p_pedido_ids)) <> (select count(distinct x) from unnest(p_pedido_ids) x) then
    raise exception 'Un pedido ya no existe.';
  end if;
  for v_p in select * from pedidos where id = any(p_pedido_ids) order by numero for update loop
    if v_p.estado <> 'cargado' then raise exception 'El pedido N° % ya se pidió al proveedor.', nro(v_p.numero); end if;
    if pedido_todo_stock(v_p) then raise exception 'El pedido N° % sale todo del stock: no hace falta pedirlo.', nro(v_p.numero); end if;
  end loop;
  select id into v_def from proveedores where activo order by creado limit 1;
  if v_def is null then raise exception 'Cargá un proveedor primero.'; end if;

  for v_prov in
    select distinct coalesce(pv.id, v_def) as prov_id
    from pedidos p cross join lateral jsonb_array_elements(p.lineas) e
    left join productos pr on pr.id = (e->>'producto_id')::uuid
    left join proveedores pv on pv.id = pr.proveedor_id
    where p.id = any(p_pedido_ids) and not coalesce((e->>'de_stock')::boolean, false)
  loop
    select coalesce(jsonb_agg(s.x order by lower(s.x->>'descripcion'), (s.x->>'factor')::numeric), '[]') into v_lineas from (
      select jsonb_build_object(
        'producto_id', pr.id, 'codigo', max(e->>'codigo'), 'descripcion', max(e->>'descripcion'), 'unidad', max(e->>'unidad'),
        'factor', max(linea_factor(e)),
        'cantidad', sum((e->>'cantidad')::numeric),
        'detalle', jsonb_agg(jsonb_build_object('pedido_id', p.id, 'pedido_numero', p.numero, 'linea_id', e->>'id',
                     'cliente_nombre', p.cliente->>'nombre', 'cantidad', (e->>'cantidad')::numeric, 'asignado', null,
                     'nota', nullif(e->>'nota', '')) order by p.numero),
        'nota', string_agg(nullif(e->>'nota', ''), ' · ' order by p.numero),
        'recepcion', 'pendiente', 'cantidad_recibida', 0,
        'precio_compra', round(coalesce(max(pr.precio_compra), 0) * max(linea_factor(e)))) as x
      from pedidos p cross join lateral jsonb_array_elements(p.lineas) e
      left join productos pr on pr.id = (e->>'producto_id')::uuid
      left join proveedores pv on pv.id = pr.proveedor_id
      where p.id = any(p_pedido_ids) and not coalesce((e->>'de_stock')::boolean, false) and coalesce(pv.id, v_def) = v_prov.prov_id
      group by pr.id, case when pr.id is null then lower(e->>'descripcion') end, lower(coalesce(e->>'unidad', 'unidad'))
    ) s;
    select array_agg(distinct (d->>'pedido_id')::uuid) into v_ids
    from jsonb_array_elements(v_lineas) l, jsonb_array_elements(l->'detalle') d;
    insert into consolidados (proveedor_id, proveedor_nombre, proveedor_telefono, pedido_ids, lineas, creado_por)
    select pv.id, pv.nombre, pv.telefono, v_ids, v_lineas, v_u.nombre from proveedores pv where pv.id = v_prov.prov_id
    returning * into v_c;
    v_creados := v_creados || v_c.id;
    v_res := v_res || jsonb_build_array(to_jsonb(v_c));
    perform auditar('Proveedor', 'Consolidado', 'N° ' || nro(v_c.numero) || ' para ' || v_c.proveedor_nombre || ' · ' ||
      jsonb_array_length(v_lineas) || ' productos · ' || cardinality(v_ids) || ' pedidos');
  end loop;

  update pedidos p set estado = 'pedido', actualizado = now(),
    consolidado_id = (select c.id from consolidados c where c.id = any(v_creados) and p.id = any(c.pedido_ids) order by c.numero limit 1)
  where p.id = any(p_pedido_ids);
  return v_res;
end $$;

create or replace function public.entregar_pedido_sin_clave(p_pedido uuid, p_recibido jsonb, p_pago_monto bigint,
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
        v_prod := mover_stock((v_l->>'producto_id')::uuid, -v_q * linea_factor(v_l), 'venta', 0, 'Entrega a ' || (v_p.cliente->>'nombre'), v_ref);
        v_costo := round(costo_ref(v_prod) * linea_factor(v_l));
      end if;
    elsif v_q < v_ef then
      perform sobrante_al_stock(v_l, v_ef - v_q, v_ref, 'El local no recibió todo');
    end if;
    continue when v_q <= 0;
    v_lineas := v_lineas || jsonb_build_array(jsonb_build_object(
      'id', v_l->>'id', 'producto_id', v_l->'producto_id', 'codigo', v_l->'codigo', 'descripcion', v_l->>'descripcion',
      'unidad', v_l->>'unidad', 'factor', linea_factor(v_l), 'nota', v_l->>'nota', 'cantidad', v_q, 'precio', (v_l->>'precio')::bigint, 'desc_pct', v_l->'desc_pct',
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
