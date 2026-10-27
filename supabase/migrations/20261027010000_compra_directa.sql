-- =================================================================
--  COMPRA DIRECTA
--  En vez de mandarle la hoja a un proveedor, el administrador va él mismo
--  a comprar: se arma una sola hoja con todo lo de las notas elegidas (sin
--  importar de qué proveedor es cada producto) y se va marcando qué se
--  compró, qué no y cuánto se pagó. Se registra igual que una recepción.
-- =================================================================
alter table public.consolidados add column directa boolean not null default false;

create function public.crear_compra_directa_sin_clave(p_pedido_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_u miembros := assert_admin();
  v_p pedidos;
  v_prov uuid;
  v_lineas jsonb;
  v_ids uuid[];
  v_c consolidados;
begin
  if coalesce(cardinality(p_pedido_ids), 0) = 0 then raise exception 'Elegí al menos un pedido.'; end if;
  if (select count(*) from pedidos where id = any(p_pedido_ids)) <> (select count(distinct x) from unnest(p_pedido_ids) x) then
    raise exception 'Un pedido ya no existe.';
  end if;
  for v_p in select * from pedidos where id = any(p_pedido_ids) order by numero for update loop
    if v_p.estado <> 'cargado' then raise exception 'El pedido N° % ya se pidió o se compró.', nro(v_p.numero); end if;
    if pedido_todo_stock(v_p) then raise exception 'El pedido N° % sale todo del stock: no hace falta comprarlo.', nro(v_p.numero); end if;
  end loop;
  -- "Proveedor" de las compras directas (no aparece para elegir).
  select id into v_prov from proveedores where nombre = 'Compra directa' order by creado limit 1;
  if v_prov is null then
    insert into proveedores (nombre, notas, activo) values ('Compra directa', 'Lo usa el sistema para las compras que hacés vos mismo.', false)
    returning id into v_prov;
  end if;

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
    where p.id = any(p_pedido_ids) and not coalesce((e->>'de_stock')::boolean, false)
    group by pr.id, case when pr.id is null then lower(e->>'descripcion') end, lower(coalesce(e->>'unidad', 'unidad'))
  ) s;
  select array_agg(distinct (d->>'pedido_id')::uuid) into v_ids
  from jsonb_array_elements(v_lineas) l, jsonb_array_elements(l->'detalle') d;
  insert into consolidados (proveedor_id, proveedor_nombre, proveedor_telefono, pedido_ids, lineas, creado_por, directa)
  values (v_prov, 'Compra directa', null, v_ids, v_lineas, v_u.nombre, true)
  returning * into v_c;
  update pedidos set estado = 'pedido', consolidado_id = v_c.id, actualizado = now() where id = any(v_ids);
  perform auditar('Proveedor', 'Compra directa', 'N° ' || nro(v_c.numero) || ' · ' || jsonb_array_length(v_lineas) || ' productos · ' ||
    cardinality(v_ids) || ' pedidos');
  return to_jsonb(v_c);
end $$;

create function public.crear_compra_directa(p_clave uuid, p_pedido_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_prev jsonb := reservar_clave(p_clave, 'crear_compra_directa');
begin
  if v_prev is not null then return v_prev; end if;
  return guardar_resultado(p_clave, crear_compra_directa_sin_clave(p_pedido_ids));
end $$;

revoke execute on function public.crear_compra_directa_sin_clave(uuid[]) from public, anon, authenticated;
revoke execute on function public.crear_compra_directa(uuid, uuid[]) from public, anon;
grant execute on function public.crear_compra_directa(uuid, uuid[]) to authenticated;
