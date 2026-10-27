-- =================================================================
--  PRUEBA DE LAS FORMAS DE VENTA (unidad / docena) contra la base real
--  Igual que circuito.sql: todo corre en un bloque que al final tira un
--  error a propósito, así la base deshace TODO. El resultado viene en el
--  mensaje: "PRUEBA OK ..." o "FALLO: ...".
-- =================================================================
do $prueba$
declare
  v_admin uuid := (select user_id from miembros where rol = 'admin' and activo order by creado limit 1);
  v_seq record;
  v_seqs jsonb := '{}';
  c1 uuid; c2 uuid;
  v_prod uuid;
  p1 jsonb; p2 jsonb;
  v_hoja jsonb;
  v_venta jsonb;
  v_l jsonb;
  v_err text;
  v_ok text[] := '{}';
begin
  if v_admin is null then raise exception 'FALLO: no hay administrador para correr la prueba'; end if;
  for v_seq in select sequencename as n, last_value as v from pg_sequences where schemaname = 'public' loop
    v_seqs := v_seqs || jsonb_build_object(v_seq.n, v_seq.v);
  end loop;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  update timbrados set activo = false where activo;
  insert into timbrados (numero, inicio, fin, siguiente, activo) values ('12345678', current_date - 30, current_date + 300, 1, true);

  c1 := (guardar_cliente(jsonb_build_object('nombre', 'ZZ Prueba Uno'))->>'id')::uuid;
  c2 := (guardar_cliente(jsonb_build_object('nombre', 'ZZ Prueba Dos'))->>'id')::uuid;

  -- ---------- Producto: Gs 36.000 la unidad y Gs 430.500 la docena ----------
  v_prod := (guardar_producto(jsonb_build_object('nombre', 'ZZ Zapatilla', 'unidad', 'unidad', 'precio_venta', 36000,
    'precio_compra', 30000, 'presentaciones', jsonb_build_array(jsonb_build_object('nombre', 'Docena', 'unidades', 12, 'precio', 430500))))->>'id')::uuid;
  if (select presentaciones->0->>'nombre' from productos where id = v_prod) <> 'docena' then raise exception 'FALLO: la forma no quedó en minúscula'; end if;
  begin
    perform guardar_producto(jsonb_build_object('id', v_prod, 'nombre', 'ZZ Zapatilla', 'presentaciones',
      jsonb_build_array(jsonb_build_object('nombre', 'docena', 'unidades', 1, 'precio', 1))));
    raise exception 'FALLO: aceptó una docena de 1 unidad';
  exception when others then
    if sqlerrm like 'FALLO%' then raise; end if;
  end;
  v_ok := v_ok || 'producto con docena'::text;

  -- 30 unidades en stock a Gs 30.000.
  perform mover_stock(v_prod, 30, 'compra', 30000, 'prueba', null);

  -- ---------- Pedidos: 2 docenas del stock + 5 unidades al proveedor; otro, 1 docena ----------
  p1 := guardar_pedido(gen_random_uuid(), null, c1, jsonb_build_array(
    jsonb_build_object('id', 'd1', 'producto_id', v_prod, 'descripcion', 'ZZ Zapatilla', 'unidad', 'docena', 'factor', 99,
                       'cantidad', 2, 'precio', 430500, 'de_stock', true),
    jsonb_build_object('id', 'u1', 'producto_id', v_prod, 'descripcion', 'ZZ Zapatilla', 'unidad', 'unidad', 'cantidad', 5, 'precio', 36000)),
    null, null, null, null);
  select value into v_l from jsonb_array_elements(p1->'lineas') where value->>'id' = 'd1';
  if (v_l->>'factor')::numeric <> 12 then raise exception 'FALLO: la docena quedó con factor % (la app mandó 99)', v_l->>'factor'; end if;
  if (v_l->>'costo')::bigint <> 360000 then raise exception 'FALLO: costo de la docena % (se esperaba 360000)', v_l->>'costo'; end if;
  p2 := guardar_pedido(gen_random_uuid(), null, c2, jsonb_build_array(
    jsonb_build_object('id', 'd2', 'producto_id', v_prod, 'descripcion', 'ZZ Zapatilla', 'unidad', 'docena', 'cantidad', 1, 'precio', 420000)),
    null, null, null, null);
  if (select precio_venta from productos where id = v_prod) <> 36000
     or (select (presentaciones->0->>'precio')::bigint from productos where id = v_prod) <> 420000 then
    raise exception 'FALLO: el último precio de la docena no quedó en la docena';
  end if;
  begin
    perform guardar_pedido(gen_random_uuid(), null, c2, jsonb_build_array(
      jsonb_build_object('producto_id', v_prod, 'descripcion', 'ZZ Zapatilla', 'unidad', 'caja', 'cantidad', 1, 'precio', 1)), null, null, null, null);
    raise exception 'FALLO: aceptó una forma que el producto no tiene';
  exception when others then
    if sqlerrm like 'FALLO%' then raise; end if;
  end;
  v_ok := v_ok || 'pedido por docena y por unidad'::text;

  -- ---------- Consolidado: docenas y unidades en renglones separados ----------
  v_hoja := crear_consolidados(gen_random_uuid(), array[(p1->>'id')::uuid, (p2->>'id')::uuid])->0;
  if jsonb_array_length(v_hoja->'lineas') <> 2 then raise exception 'FALLO: la hoja tiene % renglones (se esperaban 2)', jsonb_array_length(v_hoja->'lineas'); end if;
  if (v_hoja->'lineas'->1->>'unidad') <> 'docena' or (v_hoja->'lineas'->1->>'precio_compra')::bigint <> 360000 then
    raise exception 'FALLO: renglón de la docena mal: %', v_hoja->'lineas'->1;
  end if;
  v_ok := v_ok || 'hoja del proveedor separa docenas'::text;

  -- ---------- Recepción: la unidad a 29.500 y la docena a 348.000 (29.000 c/u) ----------
  perform registrar_recepcion(gen_random_uuid(), (v_hoja->>'id')::uuid, jsonb_build_array(
    jsonb_build_object('estado', 'completo', 'precio_compra', 29500),
    jsonb_build_object('estado', 'completo', 'precio_compra', 348000)));
  if (select precio_compra from productos where id = v_prod) <> 29000 then
    raise exception 'FALLO: precio de compra por unidad % (se esperaba 29000)', (select precio_compra from productos where id = v_prod);
  end if;
  v_ok := v_ok || 'precio de compra por unidad'::text;

  -- ---------- Entrega: el stock baja 24 (2 docenas) ----------
  v_venta := entregar_pedido(gen_random_uuid(), (p1->>'id')::uuid, '{}', 0, 'efectivo', null, null);
  if (select stock from productos where id = v_prod) <> 6 then raise exception 'FALLO: stock % después de entregar (se esperaba 6)', (select stock from productos where id = v_prod); end if;
  if (v_venta->>'total')::bigint <> 1041000 then raise exception 'FALLO: total % (se esperaba 1041000)', v_venta->>'total'; end if;
  -- costo: 2 docenas a 360.000 + 5 unidades a 29.500
  if (v_venta->>'costo_total')::bigint <> 867500 then raise exception 'FALLO: costo total % (se esperaba 867500)', v_venta->>'costo_total'; end if;
  v_ok := v_ok || 'entrega descuenta unidades'::text;

  -- ---------- Anular la venta: vuelven 2 docenas + 5 unidades = 29 ----------
  perform anular_venta(gen_random_uuid(), (v_venta->>'id')::uuid, 'prueba de anulación');
  if (select stock from productos where id = v_prod) <> 35 then raise exception 'FALLO: stock % después de anular (se esperaba 35)', (select stock from productos where id = v_prod); end if;
  v_ok := v_ok || 'anulación devuelve unidades'::text;

  -- ---------- El local 2 rechaza su docena: vuelve al stock como 12 ----------
  perform rechazar_pedido(gen_random_uuid(), (p2->>'id')::uuid, 'prueba de rechazo');
  if (select stock from productos where id = v_prod) <> 47 then raise exception 'FALLO: stock % después del rechazo (se esperaba 47)', (select stock from productos where id = v_prod); end if;
  v_ok := v_ok || 'rechazo devuelve la docena'::text;

  -- ---------- Venta directa de 3 docenas: 47 - 36 = 11 ----------
  v_venta := venta_directa(gen_random_uuid(), c1, jsonb_build_array(
    jsonb_build_object('producto_id', v_prod, 'descripcion', 'ZZ Zapatilla', 'unidad', 'docena', 'cantidad', 3, 'precio', 430500)), 0, 'efectivo', null, null);
  if (select stock from productos where id = v_prod) <> 11 then raise exception 'FALLO: stock % después de la venta directa (se esperaba 11)', (select stock from productos where id = v_prod); end if;
  begin
    perform venta_directa(gen_random_uuid(), c1, jsonb_build_array(
      jsonb_build_object('producto_id', v_prod, 'descripcion', 'ZZ Zapatilla', 'unidad', 'docena', 'cantidad', 1, 'precio', 430500)), 0, 'efectivo', null, null);
    raise exception 'FALLO: vendió una docena con 11 unidades en stock';
  exception when others then
    if sqlerrm like 'FALLO%' then raise; end if;
  end;
  v_ok := v_ok || 'venta directa por docena y control de stock'::text;

  for v_seq in select key as n, value as v from jsonb_each(v_seqs) loop
    if v_seq.v = 'null'::jsonb then perform setval('public.' || v_seq.n, 1, false);
    else perform setval('public.' || v_seq.n, (v_seq.v)::text::bigint, true); end if;
  end loop;
  raise exception 'PRUEBA OK (% pruebas): %', cardinality(v_ok), array_to_string(v_ok, ' · ');
exception when others then
  for v_seq in select key as n, value as v from jsonb_each(v_seqs) loop
    if v_seq.v = 'null'::jsonb then perform setval('public.' || v_seq.n, 1, false);
    else perform setval('public.' || v_seq.n, (v_seq.v)::text::bigint, true); end if;
  end loop;
  raise;
end $prueba$;
