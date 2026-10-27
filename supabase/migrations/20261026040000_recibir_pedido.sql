-- =================================================================
--  LLEGÓ LA MERCADERÍA DE UNA NOTA (sin hoja del proveedor)
--  Cuando la mercadería de una nota de pedido llega sin haber armado la
--  hoja del proveedor, el administrador la marca como recibida poniendo lo
--  que pagó por cada producto. La nota queda lista para entregar y facturar
--  (convertirla en venta). El último precio de compra queda en el producto.
-- =================================================================
create function public.recibir_pedido_sin_clave(p_pedido uuid, p_costos jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_u miembros := assert_admin();
  v_p pedidos;
  v_l jsonb;
  v_costo bigint;
  v_lineas jsonb := '[]';
begin
  select * into v_p from pedidos where id = p_pedido for update;
  if not found then raise exception 'El pedido ya no existe.'; end if;
  if v_p.estado = 'pedido' then
    raise exception 'Este pedido está en una hoja del proveedor: registrá la recepción desde Proveedor.';
  end if;
  if v_p.estado <> 'cargado' then raise exception 'Este pedido ya no está esperando la mercadería.'; end if;
  for v_l in select value from jsonb_array_elements(v_p.lineas) loop
    if not coalesce((v_l->>'de_stock')::boolean, false) then
      v_costo := coalesce((p_costos->>(v_l->>'id'))::bigint, -1);
      if v_costo <= 0 or v_costo > 999999999 then raise exception 'Poné el precio de compra de %.', v_l->>'descripcion'; end if;
      v_l := v_l || jsonb_build_object('estado', 'llego', 'cantidad_final', null, 'costo', v_costo);
      if v_l->>'producto_id' is not null then
        update productos set precio_compra = round(v_costo / linea_factor(v_l)) where id = (v_l->>'producto_id')::uuid;
      end if;
    end if;
    v_lineas := v_lineas || jsonb_build_array(v_l);
  end loop;
  update pedidos set lineas = v_lineas, estado = 'recibido', actualizado = now() where id = v_p.id returning * into v_p;
  perform auditar('Pedidos', 'Llegó la mercadería', 'Pedido N° ' || nro(v_p.numero) || ' · ' || (v_p.cliente->>'nombre') ||
    ' · costo ' || gs(lineas_costo(v_p.lineas)));
  return pedido_json(v_p);
end $$;

create function public.recibir_pedido(p_clave uuid, p_pedido uuid, p_costos jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_prev jsonb := reservar_clave(p_clave, 'recibir_pedido');
begin
  if v_prev is not null then return v_prev; end if;
  return guardar_resultado(p_clave, recibir_pedido_sin_clave(p_pedido, p_costos));
end $$;

revoke execute on function public.recibir_pedido_sin_clave(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.recibir_pedido(uuid, uuid, jsonb) from public, anon;
grant execute on function public.recibir_pedido(uuid, uuid, jsonb) to authenticated;
