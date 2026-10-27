-- =================================================================
--  PRESENTACIONES: un producto se vende de más de una forma
--  El stock se cuenta en la unidad del producto (la forma más chica: unidad,
--  tira, par...). Las otras formas (docena, paquete, caja) dicen cuántas
--  unidades traen y a qué precio se venden. Ej.: zapatilla, Gs 36.000 la
--  unidad y Gs 430.500 la docena (12 unidades).
--  Cada línea de pedido o de venta guarda en qué forma se vendió (unidad) y
--  cuántas unidades del stock es cada una (factor). El precio y el costo de
--  la línea son por esa forma; el stock se mueve en unidades.
-- =================================================================

alter table public.productos add column presentaciones jsonb not null default '[]'
  check (jsonb_typeof(presentaciones) = 'array');

-- Cuántas unidades del stock es una unidad de la línea (1 si no dice).
create function public.linea_factor(l jsonb) returns numeric
language sql immutable set search_path = public, pg_temp as $$
  select greatest(coalesce((l->>'factor')::numeric, 1), 0.001)
$$;

-- Revisa y ordena las presentaciones que manda la app.
create function public.limpiar_presentaciones(p_unidad text, p jsonb) returns jsonb
language plpgsql immutable set search_path = public, pg_temp as $$
declare
  v_e jsonb;
  v_nom text;
  v_u numeric;
  v_pr bigint;
  v_res jsonb := '[]';
  v_vistos text[] := array[lower(coalesce(p_unidad, 'unidad'))];
begin
  if p is null or jsonb_typeof(p) <> 'array' then return '[]'; end if;
  if jsonb_array_length(p) > 6 then raise exception 'Hasta 6 formas de venta por producto.'; end if;
  for v_e in select value from jsonb_array_elements(p) loop
    v_nom := lower(limpiar(v_e->>'nombre'));
    v_u := round(coalesce((v_e->>'unidades')::numeric, 0), 3);
    v_pr := coalesce((v_e->>'precio')::bigint, 0);
    if v_nom is null or char_length(v_nom) < 2 or char_length(v_nom) > 20 then
      raise exception 'Escribí el nombre de cada forma de venta (ej.: docena, paquete, caja).';
    end if;
    if v_nom = any(v_vistos) then raise exception 'La forma de venta "%" está repetida.', v_nom; end if;
    if v_u <= 1 or v_u > 100000 then raise exception 'En "%": cuántas % trae tiene que ser más de 1.', v_nom, coalesce(p_unidad, 'unidad'); end if;
    if v_pr < 0 or v_pr > 999999999 then raise exception 'Revisá el precio de "%".', v_nom; end if;
    v_vistos := v_vistos || v_nom;
    v_res := v_res || jsonb_build_array(jsonb_build_object('nombre', v_nom, 'unidades', v_u, 'precio', v_pr));
  end loop;
  return coalesce((select jsonb_agg(x order by (x->>'unidades')::numeric) from jsonb_array_elements(v_res) x), '[]');
end $$;

-- La forma de venta [p_nombre] del producto: {nombre, unidades, precio}.
-- Sin nombre (o con la unidad del producto) es la unidad. null si no existe.
create function public.presentacion(p public.productos, p_nombre text) returns jsonb
language sql immutable set search_path = public, pg_temp as $$
  select case
    when p_nombre is null or lower(p_nombre) = lower(p.unidad) then
      jsonb_build_object('nombre', p.unidad, 'unidades', 1, 'precio', p.precio_venta)
    else (select x from jsonb_array_elements(p.presentaciones) x where lower(x->>'nombre') = lower(p_nombre) limit 1)
  end
$$;

-- Recuerda el último precio de venta de esa forma (para el próximo pedido).
create function public.fijar_precio_venta(p_id uuid, p_nombre text, p_precio bigint) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update productos set
    precio_venta = case when lower(p_nombre) = lower(unidad) then p_precio else precio_venta end,
    presentaciones = (select coalesce(jsonb_agg(case when lower(x->>'nombre') = lower(p_nombre)
                        then x || jsonb_build_object('precio', p_precio) else x end order by o), '[]')
                      from jsonb_array_elements(presentaciones) with ordinality t(x, o))
  where id = p_id;
end $$;

revoke execute on function public.limpiar_presentaciones(text, jsonb) from public, anon, authenticated;
revoke execute on function public.presentacion(public.productos, text) from public, anon, authenticated;
revoke execute on function public.fijar_precio_venta(uuid, text, bigint) from public, anon, authenticated;
revoke execute on function public.linea_factor(jsonb) from public, anon, authenticated;

-- ---------------- Productos ----------------

create or replace function public.guardar_producto(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_u miembros := assert_miembro();
  v_id uuid := coalesce((p->>'id')::uuid, gen_random_uuid());
  v_antes productos;
  v_nombre text := limpiar(p->>'nombre');
  v_codigo text := limpiar(p->>'codigo');
  v_unidad text := coalesce(lower(limpiar(p->>'unidad')), 'unidad');
  v_pv bigint := coalesce((p->>'precio_venta')::bigint, 0);
  v_pc bigint := coalesce((p->>'precio_compra')::bigint, 0);
  v_iva smallint := coalesce((p->>'iva')::smallint, 10);
  v_pres jsonb;
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
  v_pres := limpiar_presentaciones(v_unidad, p->'presentaciones');
  insert into productos (id, codigo, nombre, unidad, categoria, marca, proveedor_id, precio_venta, precio_compra, stock_minimo, iva, activo, presentaciones)
  values (v_id, v_codigo, v_nombre, v_unidad, limpiar(p->>'categoria'), limpiar(p->>'marca'),
          (p->>'proveedor_id')::uuid, v_pv, v_pc, coalesce((p->>'stock_minimo')::numeric, 0), v_iva, coalesce((p->>'activo')::boolean, true), v_pres)
  on conflict (id) do update set codigo = excluded.codigo, nombre = excluded.nombre, unidad = excluded.unidad,
    categoria = excluded.categoria, marca = excluded.marca, proveedor_id = excluded.proveedor_id,
    precio_venta = excluded.precio_venta, precio_compra = excluded.precio_compra, stock_minimo = excluded.stock_minimo, iva = excluded.iva,
    presentaciones = excluded.presentaciones
  returning * into v_r;
  if v_antes.id is null then
    perform auditar('Inventario', 'Nuevo producto', v_nombre);
  else
    v_cambios := concat_ws(', ',
      case when v_antes.precio_venta <> v_pv then 'precio de venta ' || gs(v_antes.precio_venta) || ' → ' || gs(v_pv) end,
      case when v_antes.precio_compra <> v_pc then 'precio de compra ' || gs(v_antes.precio_compra) || ' → ' || gs(v_pc) end,
      case when v_antes.iva <> v_iva then 'IVA ' || v_antes.iva || ' % → ' || v_iva || ' %' end,
      case when v_antes.presentaciones <> v_pres then 'formas de venta' end);
    perform auditar('Inventario', 'Editó producto', v_nombre || case when v_cambios <> '' then ': ' || v_cambios else '' end, v_cambios <> '');
  end if;
  return producto_json(v_r);
end $$;

-- ---------------- Stock: siempre en unidades del producto ----------------

create or replace function public.sobrante_al_stock(l jsonb, q numeric, p_ref text, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if q <= 0 or l->>'producto_id' is null then return; end if;
  perform mover_stock((l->>'producto_id')::uuid, q * linea_factor(l), 'sobrante_pedido',
    round(coalesce((l->>'costo')::numeric, 0) / linea_factor(l))::bigint, p_motivo, p_ref);
end $$;

create or replace function public.anular_venta_sin_clave(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_v ventas;
  v_l jsonb;
  v_m text := limpiar(p_motivo);
begin
  perform assert_admin();
  if v_m is null or char_length(v_m) < 3 then raise exception 'Escribí el motivo.'; end if;
  select * into v_v from ventas where id = p_id for update;
  if not found then raise exception 'La nota de venta ya no existe.'; end if;
  if v_v.anulada then raise exception 'Esta nota ya está anulada.'; end if;
  for v_l in select value from jsonb_array_elements(v_v.lineas) loop
    if v_l->>'producto_id' is not null and exists (select 1 from productos where id = (v_l->>'producto_id')::uuid) then
      perform mover_stock((v_l->>'producto_id')::uuid, (v_l->>'cantidad')::numeric * linea_factor(v_l), 'anulacion',
        round(coalesce((v_l->>'costo')::numeric, 0) / linea_factor(v_l))::bigint, v_m, 'Nota de venta N° ' || nro(v_v.numero));
    end if;
  end loop;
  update ventas set anulada = true, motivo_anulacion = v_m, pagado = 0 where id = p_id;
  perform desaplicar_venta(p_id);
  if v_v.pedido_id is not null then
    update pedidos set estado = 'anulado', motivo = left('Nota de venta anulada: ' || v_m, 150), actualizado = now() where id = v_v.pedido_id;
  end if;
  perform aplicar_creditos(v_v.cliente_id);
  perform auditar('Entregas', 'Anuló nota de venta', 'Nota de venta N° ' || nro(v_v.numero) || ' · ' || (v_v.cliente->>'nombre') ||
    ' · ' || gs(v_v.total) || ' · Motivo: ' || v_m, true);
end $$;

-- ---------------- Pedidos ----------------

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
      'unidad', v_pres->>'nombre', 'factor', v_factor,
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

-- ---------------- Proveedor: consolidado y recepción ----------------
-- Cada forma de venta va en su renglón (3 docenas y 5 unidades no se suman).

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
                     'cliente_nombre', p.cliente->>'nombre', 'cantidad', (e->>'cantidad')::numeric, 'asignado', null) order by p.numero),
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

-- El precio de compra se pone por la forma en que se pidió (ej. por docena);
-- en el producto queda por unidad.
create or replace function public.registrar_recepcion_sin_clave(p_consolidado uuid, p_marcas jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_u miembros := assert_admin();
  v_c consolidados;
  v_l jsonb;
  v_i int;
  v_m jsonb;
  v_estado text;
  v_rec numeric;
  v_precio bigint;
  v_unit bigint;
  v_rep jsonb;
  v_suma numeric;
  v_d jsonb;
  v_asig numeric;
  v_det jsonb;
  v_nuevas jsonb := '[]';
  v_cambios text[] := '{}';
  v_antes productos;
  v_parc int := 0;
  v_falt int := 0;
  v_ped pedidos;
  v_total bigint;
begin
  select * into v_c from consolidados where id = p_consolidado for update;
  if not found then raise exception 'El consolidado ya no existe.'; end if;
  if v_c.estado = 'recibido' then raise exception 'Esta mercadería ya se recibió.'; end if;
  perform 1 from pedidos where id = any(v_c.pedido_ids) for update;

  for v_l, v_i in select e, (o - 1)::int from jsonb_array_elements(v_c.lineas) with ordinality t(e, o) loop
    v_m := p_marcas -> v_i;
    v_estado := coalesce(v_m->>'estado', 'pendiente');
    if v_estado not in ('completo', 'parcial', 'no_llego') then raise exception 'Marcá qué pasó con %.', v_l->>'descripcion'; end if;
    v_rec := case v_estado when 'completo' then (v_l->>'cantidad')::numeric when 'no_llego' then 0
                           else coalesce((v_m->>'cantidad_recibida')::numeric, 0) end;
    v_precio := coalesce((v_m->>'precio_compra')::bigint, 0);
    if v_estado = 'parcial' and (v_rec <= 0 or v_rec >= (v_l->>'cantidad')::numeric) then
      raise exception 'En %: si llegó una parte, la cantidad tiene que ser mayor a 0 y menor a %.', v_l->>'descripcion', cant((v_l->>'cantidad')::numeric);
    end if;
    if v_estado <> 'no_llego' and (v_precio <= 0 or v_precio > 999999999) then
      raise exception 'Poné el precio de compra de %.', v_l->>'descripcion';
    end if;
    v_rep := coalesce(v_m->'reparto', '{}');
    if v_estado = 'parcial' then
      v_suma := 0;
      for v_d in select value from jsonb_array_elements(v_l->'detalle') loop
        v_asig := coalesce((v_rep->>(v_d->>'linea_id'))::numeric, 0);
        if v_asig < 0 or v_asig > (v_d->>'cantidad')::numeric + 0.0001 then
          raise exception 'En %: a % no le podés dar más de lo que pidió (%).', v_l->>'descripcion', v_d->>'cliente_nombre', cant((v_d->>'cantidad')::numeric);
        end if;
        v_suma := v_suma + v_asig;
      end loop;
      if abs(v_suma - v_rec) > 0.001 then
        raise exception 'En %: el reparto suma % pero llegaron %.', v_l->>'descripcion', cant(v_suma), cant(v_rec);
      end if;
    end if;

    v_det := '[]';
    for v_d in select value from jsonb_array_elements(v_l->'detalle') loop
      v_asig := case v_estado when 'completo' then (v_d->>'cantidad')::numeric when 'no_llego' then 0
                              else coalesce((v_rep->>(v_d->>'linea_id'))::numeric, 0) end;
      v_det := v_det || jsonb_build_array(v_d || jsonb_build_object('asignado', v_asig));
      update pedidos set actualizado = now(), lineas = (
        select jsonb_agg(case when x->>'id' = v_d->>'linea_id' then
                 case when v_asig <= 0 then x || jsonb_build_object('estado', 'no_llego', 'cantidad_final', 0, 'costo', v_precio)
                      when v_asig >= (x->>'cantidad')::numeric - 0.0001 then x || jsonb_build_object('estado', 'llego', 'cantidad_final', null, 'costo', v_precio)
                      else x || jsonb_build_object('estado', 'parcial', 'cantidad_final', v_asig, 'confirmacion', 'esperando', 'costo', v_precio) end
               else x end order by o)
        from jsonb_array_elements(lineas) with ordinality t(x, o))
      where id = (v_d->>'pedido_id')::uuid;
    end loop;

    v_nuevas := v_nuevas || jsonb_build_array(v_l || jsonb_build_object('detalle', v_det, 'recepcion', v_estado,
      'cantidad_recibida', v_rec, 'precio_compra', case when v_estado = 'no_llego' then 0 else v_precio end));
    if v_estado = 'parcial' then v_parc := v_parc + 1; elsif v_estado = 'no_llego' then v_falt := v_falt + 1; end if;

    if v_estado <> 'no_llego' and v_l->>'producto_id' is not null then
      select * into v_antes from productos where id = (v_l->>'producto_id')::uuid;
      if found then
        v_unit := round(v_precio / linea_factor(v_l));
        if v_antes.precio_compra <> v_unit then
          v_cambios := v_cambios || (v_antes.nombre || ': ' || gs(v_antes.precio_compra) || ' → ' || gs(v_unit) || ' por ' || v_antes.unidad);
        end if;
        update productos set precio_compra = v_unit where id = v_antes.id;
      end if;
    end if;
  end loop;

  for v_ped in select * from pedidos where id = any(v_c.pedido_ids) loop
    if not exists (select 1 from jsonb_array_elements(v_ped.lineas) e where coalesce(e->>'estado', 'pendiente') not in ('no_llego', 'rechazada')) then
      update pedidos set estado = 'anulado', motivo = 'No llegó la mercadería del proveedor', actualizado = now() where id = v_ped.id;
      perform aplicar_creditos(v_ped.cliente_id);
    else
      update pedidos set estado = 'recibido', actualizado = now() where id = v_ped.id;
    end if;
  end loop;

  update consolidados set lineas = v_nuevas, estado = 'recibido', fecha_recepcion = now(), recibido_por = v_u.nombre
  where id = v_c.id returning * into v_c;
  select coalesce(sum(round((e->>'cantidad_recibida')::numeric * (e->>'precio_compra')::numeric)), 0) into v_total
  from jsonb_array_elements(v_nuevas) e;
  perform auditar('Proveedor', 'Recepción', 'Consolidado N° ' || nro(v_c.numero) || ' · pagado ' || gs(v_total) ||
    case when v_parc > 0 then ' · ' || v_parc || ' parciales' else '' end ||
    case when v_falt > 0 then ' · ' || v_falt || ' no llegaron' else '' end, v_parc > 0 or v_falt > 0);
  if cardinality(v_cambios) > 0 then
    perform auditar('Proveedor', 'Cambio de precio de compra', array_to_string(v_cambios, ' · '), true);
  end if;
  return to_jsonb(v_c);
end $$;

-- ---------------- Entregas y venta directa ----------------

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
      'unidad', v_l->>'unidad', 'factor', linea_factor(v_l), 'cantidad', v_q, 'precio', (v_l->>'precio')::bigint, 'desc_pct', v_l->'desc_pct',
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

create or replace function public.venta_directa_sin_clave(p_cliente uuid, p_lineas jsonb, p_pago_monto bigint,
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
  v_pres jsonb;
  v_factor numeric;
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
    v_pres := presentacion(v_prod, lower(limpiar(v_l->>'unidad')));
    if v_pres is null then raise exception '% no se vende por %.', v_prod.nombre, v_l->>'unidad'; end if;
    v_factor := (v_pres->>'unidades')::numeric;
    v_costo := round(costo_ref(v_prod) * v_factor);
    perform mover_stock(v_prod.id, -(v_l->>'cantidad')::numeric * v_factor, 'venta', 0, 'Venta directa a ' || v_c.nombre, 'Nota de venta N° ' || nro(v_numero));
    perform fijar_precio_venta(v_prod.id, v_pres->>'nombre', (v_l->>'precio')::bigint);
    v_finales := v_finales || jsonb_build_array(jsonb_build_object(
      'id', coalesce(v_l->>'id', gen_random_uuid()::text), 'producto_id', v_prod.id, 'codigo', v_prod.codigo,
      'descripcion', v_prod.nombre, 'unidad', v_pres->>'nombre', 'factor', v_factor, 'cantidad', round((v_l->>'cantidad')::numeric, 3),
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
