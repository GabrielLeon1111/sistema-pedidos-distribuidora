-- =================================================================
--  PEDIDOS SIN CONEXIÓN
--  Cada teléfono reserva un bloque de números de pedido mientras tiene
--  señal. Sin señal, cada nota toma el siguiente número de su bloque: el
--  número es definitivo desde que se crea (nunca cambia ni se repite).
--  Al volver la señal, la app manda cada nota con su id, su número y la
--  fecha en que se levantó, con la clave contra duplicados de siempre.
-- =================================================================

create table public.bloques_numeros (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  desde bigint not null,
  hasta bigint not null check (hasta >= desde),
  creado timestamptz not null default now()
);
create index bloques_numeros_usuario on public.bloques_numeros (user_id);
alter table public.bloques_numeros enable row level security;
revoke all on public.bloques_numeros from anon, authenticated;
create policy "cada uno ve sus bloques" on public.bloques_numeros for select to authenticated using (user_id = auth.uid());
grant select on public.bloques_numeros to authenticated;

-- Toma [p_cantidad] números seguidos de la numeración de pedidos. Todos los
-- números de pedido salen por acá (con un candado), así nunca se pisan.
create function public.tomar_numeros_pedido(p_cantidad int) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_desde bigint;
begin
  perform pg_advisory_xact_lock(hashtext('nro_pedido'));
  v_desde := nextval('nro_pedido');
  if p_cantidad > 1 then perform setval('nro_pedido', v_desde + p_cantidad - 1, true); end if;
  return v_desde;
end $$;

-- El teléfono reserva un bloque para levantar pedidos sin señal.
create function public.reservar_numeros_pedido(p_cantidad int default 20) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_u miembros := assert_miembro();
  v_n int := least(greatest(coalesce(p_cantidad, 20), 1), 100);
  v_desde bigint := tomar_numeros_pedido(v_n);
begin
  insert into bloques_numeros (user_id, desde, hasta) values (v_u.user_id, v_desde, v_desde + v_n - 1);
  return jsonb_build_object('desde', v_desde, 'hasta', v_desde + v_n - 1);
end $$;

-- guardar_pedido ahora acepta el número (de un bloque reservado por quien lo
-- levantó) y la fecha en que se levantó; y si el id todavía no existe, crea
-- el pedido con ese id (el que puso el teléfono).
drop function public.guardar_pedido(uuid, uuid, uuid, jsonb, text, timestamptz);
drop function public.guardar_pedido_sin_clave(uuid, uuid, jsonb, text, timestamptz);

create function public.guardar_pedido_sin_clave(p_id uuid, p_cliente_id uuid, p_lineas jsonb,
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

create function public.guardar_pedido(p_clave uuid, p_id uuid, p_cliente_id uuid, p_lineas jsonb, p_observaciones text,
  p_fecha_entrega timestamptz, p_numero bigint, p_fecha timestamptz) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_prev jsonb := reservar_clave(p_clave, 'guardar_pedido');
begin
  if v_prev is not null then return v_prev; end if;
  return guardar_resultado(p_clave, guardar_pedido_sin_clave(p_id, p_cliente_id, p_lineas, p_observaciones, p_fecha_entrega, p_numero, p_fecha));
end $$;

revoke execute on function public.tomar_numeros_pedido(int) from public, anon, authenticated;
revoke execute on function public.guardar_pedido_sin_clave(uuid, uuid, jsonb, text, timestamptz, bigint, timestamptz) from public, anon, authenticated;
revoke execute on function public.reservar_numeros_pedido(int) from public, anon;
grant execute on function public.reservar_numeros_pedido(int) to authenticated;
revoke execute on function public.guardar_pedido(uuid, uuid, uuid, jsonb, text, timestamptz, bigint, timestamptz) from public, anon;
grant execute on function public.guardar_pedido(uuid, uuid, uuid, jsonb, text, timestamptz, bigint, timestamptz) to authenticated;
