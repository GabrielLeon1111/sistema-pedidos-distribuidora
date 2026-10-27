-- =================================================================
--  OPERACIONES DEL NEGOCIO (iguales a lib/repositories/*)
--  Cada función es una transacción: si algo falla, no queda nada a medias.
-- =================================================================

create or replace function public.estado_pedido_texto(e text) returns text language sql immutable as $$
  select case e when 'cargado' then 'Cargado' when 'pedido' then 'Pedido al proveedor' when 'recibido' then 'Listo para entregar'
    when 'pendiente' then 'Entrega pendiente' when 'entregado' then 'Entregado' when 'rechazado' then 'Rechazado' when 'anulado' then 'Anulado' else e end
$$;

create or replace function public.pedido_esperando(p public.pedidos) returns boolean language sql immutable as $$
  select exists (select 1 from jsonb_array_elements(p.lineas) e where e->>'confirmacion' = 'esperando')
$$;

create or replace function public.pedido_todo_stock(p public.pedidos) returns boolean language sql immutable as $$
  select jsonb_array_length(p.lineas) > 0 and not exists (select 1 from jsonb_array_elements(p.lineas) e where not coalesce((e->>'de_stock')::boolean, false))
$$;

create or replace function public.pedido_entregable(p public.pedidos) returns boolean language sql immutable as $$
  select not pedido_esperando(p) and (p.estado in ('recibido', 'pendiente') or (p.estado = 'cargado' and pedido_todo_stock(p)))
$$;

-- ---------------- Nota de pedido ----------------
-- Nueva o editada (solo mientras no se pidió al proveedor). Los productos que no
-- existen se agregan solos y se recuerda el último precio de venta.
create or replace function public.guardar_pedido(p_id uuid, p_cliente_id uuid, p_lineas jsonb,
  p_observaciones text default null, p_fecha_entrega timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
    if v_nom is null or char_length(v_nom) < 2 then raise exception 'Hay un producto sin nombre.'; end if;
    if coalesce((v_l->>'cantidad')::numeric, 0) <= 0 or (v_l->>'cantidad')::numeric > 100000 then raise exception 'Revisá la cantidad de %.', v_nom; end if;
    if coalesce((v_l->>'precio')::bigint, -1) < 0 or (v_l->>'precio')::bigint > 999999999 then raise exception 'Revisá el precio de %.', v_nom; end if;
    if v_l->>'desc_pct' is not null and ((v_l->>'desc_pct')::numeric < 0 or (v_l->>'desc_pct')::numeric > 100) then
      raise exception 'El descuento de % tiene que ser de 0 a 100 %%.', v_nom;
    end if;
    if coalesce((v_l->>'desc_monto')::bigint, 0) < 0 then raise exception 'Revisá el descuento de %.', v_nom; end if;

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
      insert into productos (codigo, nombre, unidad, proveedor_id, precio_venta)
      values (v_cod, v_nom, coalesce(limpiar(v_l->>'unidad'), 'unidad'), v_prov, (v_l->>'precio')::bigint)
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
      'de_stock', v_stock,
      -- Lo que sale del stock ya tiene costo; lo pedido se completa al recibir.
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

-- Anula un pedido con motivo. Si la mercadería ya llegó, entra al stock.
create or replace function public.anular_pedido(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_u miembros := assert_miembro();
  v_m text := limpiar(p_motivo);
  v_p pedidos;
  v_l jsonb;
begin
  if v_m is null or char_length(v_m) < 3 then raise exception 'Escribí el motivo.'; end if;
  select * into v_p from pedidos where id = p_id for update;
  if not found then raise exception 'El pedido ya no existe.'; end if;
  if v_p.estado in ('entregado', 'rechazado', 'anulado') then raise exception 'Este pedido ya está cerrado.'; end if;
  if v_u.rol <> 'admin' and v_p.estado <> 'cargado' then
    raise exception using errcode = '42501', message = 'Tu usuario no tiene permiso para hacer esto.';
  end if;
  if v_p.estado = 'pedido' then
    raise exception 'Ya se pidió al proveedor. Registrá la recepción y después anulalo: lo que llegue entra al stock.';
  end if;
  if v_p.estado in ('recibido', 'pendiente') then
    for v_l in select value from jsonb_array_elements(v_p.lineas) loop
      if not coalesce((v_l->>'de_stock')::boolean, false) then
        perform sobrante_al_stock(v_l, linea_efectiva(v_l), 'Pedido N° ' || nro(v_p.numero), 'Pedido anulado: ' || v_m);
      end if;
    end loop;
  end if;
  update pedidos set estado = 'anulado', motivo = v_m, actualizado = now() where id = p_id;
  perform aplicar_creditos(v_p.cliente_id);
  perform auditar('Pedidos', 'Anuló pedido', 'Pedido N° ' || nro(v_p.numero) || ' · ' || (v_p.cliente->>'nombre') || ' · Motivo: ' || v_m, true);
end $$;

-- El local acepta (o no) la cantidad parcial que llegó de un producto.
create or replace function public.confirmar_parcial(p_pedido uuid, p_linea text, p_acepta boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_p pedidos;
  v_l jsonb;
  v_nueva jsonb;
  v_lineas jsonb;
  v_anular boolean;
begin
  perform assert_miembro();
  select * into v_p from pedidos where id = p_pedido for update;
  if not found then raise exception 'El pedido ya no existe.'; end if;
  select value into v_l from jsonb_array_elements(v_p.lineas) where value->>'id' = p_linea;
  if v_l is null or v_l->>'confirmacion' is distinct from 'esperando' then
    raise exception 'Ese producto ya no está esperando confirmación.';
  end if;
  if p_acepta then
    v_nueva := v_l || jsonb_build_object('confirmacion', 'aceptada');
  else
    perform sobrante_al_stock(v_l, linea_efectiva(v_l), 'Pedido N° ' || nro(v_p.numero), 'El local no aceptó la cantidad parcial');
    v_nueva := v_l || jsonb_build_object('estado', 'rechazada', 'confirmacion', null);
  end if;
  select jsonb_agg(case when x->>'id' = p_linea then v_nueva else x end order by o) into v_lineas
  from jsonb_array_elements(v_p.lineas) with ordinality t(x, o);
  v_anular := not exists (select 1 from jsonb_array_elements(v_lineas) e where coalesce(e->>'estado', 'pendiente') not in ('no_llego', 'rechazada'));
  update pedidos set lineas = v_lineas, actualizado = now(),
    estado = case when v_anular then 'anulado' else estado end,
    motivo = case when v_anular then 'No llegó la mercadería o el local no la aceptó' else motivo end
  where id = p_pedido;
  if v_anular then perform aplicar_creditos(v_p.cliente_id); end if;
  perform auditar('Pedidos', case when p_acepta then 'Local aceptó parcial' else 'Local no aceptó parcial' end,
    'Pedido N° ' || nro(v_p.numero) || ' · ' || (v_l->>'descripcion') || ': ' || cant(linea_efectiva(v_l)) || ' de ' || cant((v_l->>'cantidad')::numeric),
    not p_acepta);
end $$;

-- ---------------- Consolidado del día ----------------
-- Suma los pedidos elegidos por producto. Si hay varios proveedores, sale una hoja para cada uno.
create or replace function public.crear_consolidados(p_pedido_ids uuid[]) returns jsonb
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
    select coalesce(jsonb_agg(s.x order by lower(s.x->>'descripcion')), '[]') into v_lineas from (
      select jsonb_build_object(
        'producto_id', pr.id, 'codigo', max(e->>'codigo'), 'descripcion', max(e->>'descripcion'), 'unidad', max(e->>'unidad'),
        'cantidad', sum((e->>'cantidad')::numeric),
        'detalle', jsonb_agg(jsonb_build_object('pedido_id', p.id, 'pedido_numero', p.numero, 'linea_id', e->>'id',
                     'cliente_nombre', p.cliente->>'nombre', 'cantidad', (e->>'cantidad')::numeric, 'asignado', null) order by p.numero),
        'recepcion', 'pendiente', 'cantidad_recibida', 0, 'precio_compra', coalesce(max(pr.precio_compra), 0)) as x
      from pedidos p cross join lateral jsonb_array_elements(p.lineas) e
      left join productos pr on pr.id = (e->>'producto_id')::uuid
      left join proveedores pv on pv.id = pr.proveedor_id
      where p.id = any(p_pedido_ids) and not coalesce((e->>'de_stock')::boolean, false) and coalesce(pv.id, v_def) = v_prov.prov_id
      group by pr.id, case when pr.id is null then lower(e->>'descripcion') end
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

-- ---------------- Recepción de mercadería ----------------
-- p_marcas: una marca por línea del consolidado (en el mismo orden):
--   {"estado": "completo|parcial|no_llego", "cantidad_recibida": n, "precio_compra": n, "reparto": {"<linea_id>": n}}
create or replace function public.registrar_recepcion(p_consolidado uuid, p_marcas jsonb) returns jsonb
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

    -- Último precio de compra del producto.
    if v_estado <> 'no_llego' and v_l->>'producto_id' is not null then
      select * into v_antes from productos where id = (v_l->>'producto_id')::uuid;
      if found then
        if v_antes.precio_compra <> v_precio then
          v_cambios := v_cambios || (v_antes.nombre || ': ' || gs(v_antes.precio_compra) || ' → ' || gs(v_precio));
        end if;
        update productos set precio_compra = v_precio where id = v_antes.id;
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

-- ---------------- Cobro al entregar (interna) ----------------
create or replace function public.cobrar_venta(p_venta uuid, p_monto bigint, p_metodo text, p_sena bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_v ventas;
  v_max bigint;
  v_pg pagos;
begin
  select * into v_v from ventas where id = p_venta for update;
  v_max := v_v.total - p_sena;
  if coalesce(p_monto, 0) < 0 then raise exception 'El monto no puede ser negativo.'; end if;
  if p_monto > 0 and p_monto > v_max then
    raise exception 'El pago no puede ser mayor a lo que falta: %.',
      gs(greatest(v_max, 0)) || case when p_sena > 0 then ' (ya dejó ' || gs(p_sena) || ' de seña)' else '' end;
  end if;
  if p_monto > 0 then
    if p_metodo not in ('efectivo', 'transferencia', 'qr') then raise exception 'Elegí cómo pagó.'; end if;
    insert into pagos (cliente_id, cliente_nombre, monto, metodo, nota, aplicaciones, registrado_por)
    values (v_v.cliente_id, v_v.cliente->>'nombre', p_monto, p_metodo, 'Pago al entregar Nota de venta N° ' || nro(v_v.numero),
      jsonb_build_array(jsonb_build_object('venta_id', v_v.id, 'venta_numero', v_v.numero, 'monto', p_monto)),
      (select nombre from miembros where user_id = auth.uid()))
    returning * into v_pg;
    update ventas set pagado = p_monto where id = v_v.id;
    perform auditar('Cobros', 'Pago', 'Recibo N° ' || nro(v_pg.numero) || ' · ' || v_pg.cliente_nombre || ' · ' || gs(p_monto) ||
      ' (' || initcap(p_metodo) || ')');
  end if;
  perform aplicar_creditos(v_v.cliente_id);
end $$;

-- ---------------- Entrega ----------------
-- p_recibido: {"<linea_id>": cantidad} con lo que el local recibió (null = todo).
-- Lo que no recibió entra al stock con lo que se pagó.
create or replace function public.entregar_pedido(p_pedido uuid, p_recibido jsonb default null, p_pago_monto bigint default 0,
  p_pago_metodo text default 'efectivo', p_observaciones text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
      'de_stock', coalesce((v_l->>'de_stock')::boolean, false), 'costo', v_costo,
      'estado', 'llego', 'cantidad_final', null, 'confirmacion', null));
  end loop;
  if jsonb_array_length(v_lineas) = 0 then
    raise exception 'No hay nada para entregar. Si el local no recibió nada, marcá "No recibió el pedido".';
  end if;
  insert into ventas (cliente_id, cliente, pedido_id, pedido_numero, vendedor_nombre, lineas, observaciones, total, costo_total, entrega_parcial)
  values (v_p.cliente_id, v_p.cliente, v_p.id, v_p.numero, coalesce(v_p.vendedor_nombre, v_u.nombre), v_lineas,
          coalesce(limpiar_multi(p_observaciones), v_p.observaciones), lineas_total(v_lineas), lineas_costo(v_lineas), v_parcial)
  returning * into v_v;
  update pedidos set estado = 'entregado', venta_id = v_v.id, actualizado = now() where id = v_p.id;
  perform auditar('Entregas', case when v_parcial then 'Entrega parcial' else 'Entrega' end,
    v_ref || ' · ' || (v_p.cliente->>'nombre') || ' · Nota de venta N° ' || nro(v_v.numero) || ' por ' || gs(v_v.total), v_parcial);
  perform cobrar_venta(v_v.id, coalesce(p_pago_monto, 0), p_pago_metodo, sena_de_pedido(v_p.id));
  select * into v_v from ventas where id = v_v.id;
  return to_jsonb(v_v);
end $$;

-- El local no estaba: el pedido queda pendiente con nueva fecha.
create or replace function public.no_estaba(p_pedido uuid, p_fecha timestamptz) returns void
language plpgsql security definer set search_path = public as $$
declare v_p pedidos;
begin
  perform assert_admin();
  select * into v_p from pedidos where id = p_pedido for update;
  if not found then raise exception 'El pedido ya no existe.'; end if;
  if not pedido_entregable(v_p) and not pedido_esperando(v_p) then raise exception 'Este pedido no está para entregar.'; end if;
  update pedidos set estado = 'pendiente', fecha_entrega = p_fecha, actualizado = now() where id = p_pedido;
  perform auditar('Entregas', 'Local no estaba', 'Pedido N° ' || nro(v_p.numero) || ' · ' || (v_p.cliente->>'nombre') ||
    ' · nueva fecha ' || to_char(p_fecha at time zone 'America/Asuncion', 'DD/MM/YYYY'));
end $$;

-- El local no recibió nada: queda rechazado con el motivo y la mercadería entra al stock.
create or replace function public.rechazar_pedido(p_pedido uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_p pedidos;
  v_l jsonb;
  v_m text := limpiar(p_motivo);
begin
  perform assert_admin();
  if v_m is null or char_length(v_m) < 3 then raise exception 'Escribí el motivo.'; end if;
  select * into v_p from pedidos where id = p_pedido for update;
  if not found then raise exception 'El pedido ya no existe.'; end if;
  if v_p.estado not in ('recibido', 'pendiente', 'cargado') then raise exception 'Este pedido no está para entregar.'; end if;
  if v_p.estado = 'cargado' and not pedido_todo_stock(v_p) then raise exception 'Todavía no llegó la mercadería de este pedido.'; end if;
  if v_p.estado <> 'cargado' then
    for v_l in select value from jsonb_array_elements(v_p.lineas) loop
      if not coalesce((v_l->>'de_stock')::boolean, false) then
        perform sobrante_al_stock(v_l, linea_efectiva(v_l), 'Pedido N° ' || nro(v_p.numero), 'Pedido rechazado: ' || v_m);
      end if;
    end loop;
  end if;
  update pedidos set estado = 'rechazado', motivo = v_m, actualizado = now() where id = p_pedido;
  perform aplicar_creditos(v_p.cliente_id);
  perform auditar('Entregas', 'Pedido rechazado', 'Pedido N° ' || nro(v_p.numero) || ' · ' || (v_p.cliente->>'nombre') || ' · ' ||
    gs(lineas_total(v_p.lineas)) || ' · Motivo: ' || v_m, true);
end $$;

-- Venta directa desde el stock, sin pedido previo.
create or replace function public.venta_directa(p_cliente uuid, p_lineas jsonb, p_pago_monto bigint default 0,
  p_pago_metodo text default 'efectivo', p_observaciones text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
      'de_stock', true, 'costo', v_costo, 'estado', 'llego', 'cantidad_final', null, 'confirmacion', null));
  end loop;
  insert into ventas (numero, cliente_id, cliente, vendedor_nombre, lineas, observaciones, total, costo_total)
  values (v_numero, v_c.id, jsonb_build_object('nombre', v_c.nombre, 'razon_social', v_c.razon_social, 'ruc', v_c.ruc,
            'direccion', v_c.direccion, 'telefono', v_c.telefono, 'contacto', v_c.contacto),
          v_u.nombre, v_finales, limpiar_multi(p_observaciones), lineas_total(v_finales), lineas_costo(v_finales))
  returning * into v_v;
  perform auditar('Entregas', 'Venta directa', 'Nota de venta N° ' || nro(v_v.numero) || ' · ' || v_c.nombre || ' · ' || gs(v_v.total));
  perform cobrar_venta(v_v.id, coalesce(p_pago_monto, 0), p_pago_metodo, 0);
  select * into v_v from ventas where id = v_v.id;
  return to_jsonb(v_v);
end $$;

-- Anula una nota de venta: la mercadería vuelve al stock y lo pagado queda a favor del local.
create or replace function public.anular_venta(p_id uuid, p_motivo text) returns void
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
      perform mover_stock((v_l->>'producto_id')::uuid, (v_l->>'cantidad')::numeric, 'anulacion', coalesce((v_l->>'costo')::bigint, 0),
        v_m, 'Nota de venta N° ' || nro(v_v.numero));
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

-- ---------------- Cobros ----------------
-- Pago del local: va primero a p_venta (si se eligió) y lo que sobra a las notas más
-- viejas. Con p_pedido es una seña que espera la entrega de ese pedido.
create or replace function public.registrar_pago(p_cliente uuid, p_monto bigint, p_metodo text, p_fecha timestamptz default null,
  p_nota text default null, p_venta uuid default null, p_pedido uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_u miembros := assert_admin();
  v_c clientes;
  v_ped pedidos;
  v_v ventas;
  v_senas bigint;
  v_deuda bigint;
  v_apps jsonb := '[]';
  v_m bigint;
  v_pg pagos;
begin
  select * into v_c from clientes where id = p_cliente;
  if not found then raise exception 'El local ya no existe.'; end if;
  if p_monto is null or p_monto <= 0 or p_monto > 999999999 then raise exception 'Revisá el monto.'; end if;
  if p_metodo not in ('efectivo', 'transferencia', 'qr') then raise exception 'Elegí cómo pagó.'; end if;
  if p_fecha > now() + interval '5 minutes' then raise exception 'La fecha no puede ser futura.'; end if;
  if p_pedido is not null then
    select * into v_ped from pedidos where id = p_pedido for update;
    if not found then raise exception 'El pedido ya no existe.'; end if;
    if v_ped.estado in ('entregado', 'rechazado', 'anulado') then
      raise exception 'Este pedido ya está cerrado: registrá el pago en la cuenta del local.';
    end if;
    v_senas := sena_de_pedido(p_pedido);
    if v_senas + p_monto > lineas_total(v_ped.lineas) then
      raise exception 'La seña no puede pasar el total del pedido (%).',
        gs(lineas_total(v_ped.lineas)) || case when v_senas > 0 then ', ya dejó ' || gs(v_senas) else '' end;
    end if;
  else
    select coalesce(sum(total - pagado), 0) into v_deuda from ventas where cliente_id = p_cliente and not anulada;
    if p_monto > v_deuda then
      if v_deuda = 0 then
        raise exception '% no debe nada. Si es un adelanto de un pedido, registralo como seña desde el pedido.', v_c.nombre;
      end if;
      raise exception 'El pago es mayor a lo que debe (%).', gs(v_deuda);
    end if;
  end if;
  if p_venta is not null then
    select * into v_v from ventas where id = p_venta for update;
    if not found then raise exception 'La nota de venta ya no existe.'; end if;
    if v_v.cliente_id <> p_cliente then raise exception 'Esa nota es de otro local.'; end if;
    v_m := least(p_monto, greatest(v_v.total - v_v.pagado, 0));
    if v_m > 0 and not v_v.anulada then
      v_apps := jsonb_build_array(jsonb_build_object('venta_id', v_v.id, 'venta_numero', v_v.numero, 'monto', v_m));
      update ventas set pagado = pagado + v_m where id = v_v.id;
    end if;
  end if;
  insert into pagos (fecha, cliente_id, cliente_nombre, monto, metodo, nota, pedido_id, pedido_numero, aplicaciones, registrado_por)
  values (coalesce(p_fecha, now()), v_c.id, v_c.nombre, p_monto, p_metodo, limpiar(p_nota), v_ped.id, v_ped.numero, v_apps, v_u.nombre)
  returning * into v_pg;
  perform aplicar_creditos(v_c.id);
  perform auditar('Cobros', case when v_ped.id is null then 'Pago' else 'Seña' end,
    'Recibo N° ' || nro(v_pg.numero) || ' · ' || v_c.nombre || ' · ' || gs(p_monto) || ' (' || initcap(p_metodo) || ')' ||
    case when v_ped.id is null then '' else ' · Pedido N° ' || nro(v_ped.numero) end);
  select * into v_pg from pagos where id = v_pg.id;
  return to_jsonb(v_pg);
end $$;

create or replace function public.anular_pago(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_pg pagos;
  v_m text := limpiar(p_motivo);
begin
  perform assert_admin();
  if v_m is null or char_length(v_m) < 3 then raise exception 'Escribí el motivo.'; end if;
  select * into v_pg from pagos where id = p_id for update;
  if not found then raise exception 'El pago ya no existe.'; end if;
  if v_pg.anulado then raise exception 'Este pago ya está anulado.'; end if;
  update pagos set anulado = true, motivo_anulacion = v_m, aplicaciones = '[]' where id = p_id;
  perform recalcular_pagado(v_pg.cliente_id);
  perform aplicar_creditos(v_pg.cliente_id);
  perform auditar('Cobros', 'Anuló pago', 'Recibo N° ' || nro(v_pg.numero) || ' · ' || v_pg.cliente_nombre || ' · ' || gs(v_pg.monto) ||
    ' · Motivo: ' || v_m, true);
end $$;

-- =================================================================
--  QUIÉN PUEDE LLAMAR A QUÉ
--  Las funciones de ayuda (mover_stock, aplicar_creditos, auditar…) no se
--  pueden llamar desde la app. Solo las operaciones de arriba, que validan
--  el permiso adentro.
-- =================================================================
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

grant execute on function
  public.es_miembro(), public.es_admin(),
  public.listar_productos(boolean), public.listar_pedidos(text[], uuid, timestamptz, timestamptz),
  public.obtener_pedido(uuid), public.senas_pedido(uuid), public.rechazos_cliente(uuid),
  public.guardar_cliente(jsonb), public.activar_cliente(uuid, boolean),
  public.guardar_producto(jsonb), public.activar_producto(uuid, boolean),
  public.guardar_proveedor(jsonb), public.guardar_negocio(jsonb),
  public.registrar_gasto(text, bigint, timestamptz, text, text), public.anular_gasto(uuid, text),
  public.ajustar_stock(uuid, numeric, text), public.salida_stock(uuid, numeric, text, text),
  public.registrar_compra(uuid, text, text, jsonb),
  public.guardar_pedido(uuid, uuid, jsonb, text, timestamptz), public.anular_pedido(uuid, text),
  public.confirmar_parcial(uuid, text, boolean), public.crear_consolidados(uuid[]),
  public.registrar_recepcion(uuid, jsonb), public.entregar_pedido(uuid, jsonb, bigint, text, text),
  public.no_estaba(uuid, timestamptz), public.rechazar_pedido(uuid, text),
  public.venta_directa(uuid, jsonb, bigint, text, text), public.anular_venta(uuid, text),
  public.registrar_pago(uuid, bigint, text, timestamptz, text, uuid, uuid), public.anular_pago(uuid, text)
to authenticated;
