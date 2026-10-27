-- =================================================================
--  PRUEBA DEL CIRCUITO COMPLETO (contra la base real)
--  Pedido → consolidado → recepción con parcial → confirmación → entrega
--  con factura y cobro, más anti-duplicados y permisos del vendedor.
--
--  Todo corre adentro de un bloque que al final tira un error a propósito:
--  así la base deshace TODO (no queda ningún dato de prueba). El resultado
--  viene en ese mensaje: "PRUEBA OK ..." o "FALLO: ...".
--  Los números de pedido/venta/recibo/consolidado se dejan como estaban.
--
--  Correrlo con el SQL Editor de Supabase o con execute_sql.
-- =================================================================
do $prueba$
declare
  v_admin uuid := (select user_id from miembros where rol = 'admin' and activo order by creado limit 1);
  v_vend uuid := gen_random_uuid();
  v_seq record;
  v_seqs jsonb := '{}';
  c1 uuid; c2 uuid;
  p1 jsonb; p1b jsonb; p2 jsonb;
  k_p1 uuid := gen_random_uuid();
  k_ent uuid := gen_random_uuid();
  k_mal uuid := gen_random_uuid();
  v_hojas jsonb; v_hoja jsonb;
  l_aceite1 text; l_azucar1 text; l_aceite2 text;
  v_venta jsonb; v_venta2 jsonb;
  v_t_sig int;
  v_err text;
  v_ok text[] := '{}';
begin
  if v_admin is null then raise exception 'FALLO: no hay administrador para correr la prueba'; end if;

  -- Los números de documento no vuelven atrás solos: se anotan para dejarlos igual.
  for v_seq in select sequencename as n, last_value as v from pg_sequences where schemaname = 'public' loop
    v_seqs := v_seqs || jsonb_build_object(v_seq.n, v_seq.v);
  end loop;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  -- Timbrado de prueba vigente (el real queda como estaba al deshacer).
  update timbrados set activo = false where activo;
  insert into timbrados (numero, inicio, fin, siguiente, activo)
  values ('12345678', current_date - 30, current_date + 300, 1481, true);

  c1 := (guardar_cliente(jsonb_build_object('nombre', 'ZZ Prueba Uno', 'ruc', '1234567-8'))->>'id')::uuid;
  c2 := (guardar_cliente(jsonb_build_object('nombre', 'ZZ Prueba Dos'))->>'id')::uuid;

  -- ---------- Pedido guardado dos veces con la misma clave: uno solo ----------
  p1 := guardar_pedido(k_p1, null, c1, jsonb_build_array(
    jsonb_build_object('id', 'a1', 'descripcion', 'ZZ Aceite', 'cantidad', 6, 'precio', 15000),
    jsonb_build_object('id', 'z1', 'descripcion', 'ZZ Azúcar', 'cantidad', 10, 'precio', 6000, 'desc_pct', 10)), null, null, null, null);
  p1b := guardar_pedido(k_p1, null, c1, jsonb_build_array(
    jsonb_build_object('id', 'a1', 'descripcion', 'ZZ Aceite', 'cantidad', 6, 'precio', 15000)), null, null, null, null);
  if p1b->>'id' <> p1->>'id' or (select count(*) from pedidos where cliente_id = c1) <> 1 then
    raise exception 'FALLO: el pedido repetido con la misma clave se duplicó';
  end if;
  v_ok := v_ok || 'pedido repetido = uno solo'::text;

  p2 := guardar_pedido(gen_random_uuid(), null, c2, jsonb_build_array(
    jsonb_build_object('id', 'a2', 'descripcion', 'zz aceite', 'cantidad', 4, 'precio', 15000)), null, null, null, null);
  if (select count(*) from productos where lower(nombre) = 'zz aceite') <> 1 then
    raise exception 'FALLO: el producto se recordó dos veces';
  end if;

  -- Seña de 20.000 para el pedido 1.
  perform registrar_pago(gen_random_uuid(), c1, 20000, 'efectivo', null, null, null, (p1->>'id')::uuid);

  -- ---------- Consolidado ----------
  v_hojas := crear_consolidados(gen_random_uuid(), array[(p1->>'id')::uuid, (p2->>'id')::uuid]);
  if jsonb_array_length(v_hojas) <> 1 then raise exception 'FALLO: se esperaba 1 hoja y salieron %', jsonb_array_length(v_hojas); end if;
  v_hoja := v_hojas->0;
  if (select estado from pedidos where id = (p1->>'id')::uuid) <> 'pedido' then raise exception 'FALLO: el pedido no pasó a "pedido"'; end if;
  v_ok := v_ok || 'consolidado'::text;

  -- Ids de las líneas (el servidor puede reescribirlas).
  select e->>'id' into l_aceite1 from pedidos p, jsonb_array_elements(p.lineas) e where p.id = (p1->>'id')::uuid and e->>'descripcion' ilike 'zz aceite';
  select e->>'id' into l_azucar1 from pedidos p, jsonb_array_elements(p.lineas) e where p.id = (p1->>'id')::uuid and e->>'descripcion' ilike 'zz azúcar';
  select e->>'id' into l_aceite2 from pedidos p, jsonb_array_elements(p.lineas) e where p.id = (p2->>'id')::uuid;

  -- ---------- Recepción: aceite llegó 8 de 10 (5 y 3), azúcar completo ----------
  perform registrar_recepcion(gen_random_uuid(), (v_hoja->>'id')::uuid, (
    select jsonb_agg(case when l->>'descripcion' ilike 'zz aceite'
      then jsonb_build_object('estado', 'parcial', 'cantidad_recibida', 8, 'precio_compra', 12000,
             'reparto', jsonb_build_object(l_aceite1, 5, l_aceite2, 3))
      else jsonb_build_object('estado', 'completo', 'cantidad_recibida', 10, 'precio_compra', 4500) end order by o)
    from jsonb_array_elements(v_hoja->'lineas') with ordinality t(l, o)));
  v_ok := v_ok || 'recepción con parcial'::text;

  -- El local 2 no acepta la parte: su pedido queda anulado. El 1 acepta.
  perform confirmar_parcial(gen_random_uuid(), (p2->>'id')::uuid, l_aceite2, false);
  perform confirmar_parcial(gen_random_uuid(), (p1->>'id')::uuid, l_aceite1, true);
  if (select estado from pedidos where id = (p2->>'id')::uuid) <> 'anulado' then raise exception 'FALLO: el pedido 2 debía quedar anulado'; end if;
  v_ok := v_ok || 'confirmación de parciales'::text;

  -- ---------- Entrega dos veces con la misma clave: una venta, una factura, un cobro ----------
  v_venta := entregar_pedido(k_ent, (p1->>'id')::uuid, jsonb_build_object(l_azucar1, 9), 10000, 'efectivo', null, '001-001-0000012');
  v_venta2 := entregar_pedido(k_ent, (p1->>'id')::uuid, jsonb_build_object(l_azucar1, 9), 10000, 'efectivo', null, '001-001-0000012');
  if v_venta2->>'id' <> v_venta->>'id' or (select count(*) from ventas where cliente_id = c1) <> 1 then
    raise exception 'FALLO: la entrega repetida generó otra venta';
  end if;
  select siguiente into v_t_sig from timbrados where activo;
  if v_t_sig <> 1482 or (v_venta->>'factura_numero')::int <> 1481 then
    raise exception 'FALLO: la factura debía ser 1481 y el timbrado quedar en 1482 (factura %, siguiente %)', v_venta->>'factura_numero', v_t_sig;
  end if;
  -- 5 × 15.000 + 9 × 6.000 − 10 % = 75.000 + 48.600
  if (v_venta->>'total')::bigint <> 123600 then raise exception 'FALLO: total de la venta % (se esperaba 123600)', v_venta->>'total'; end if;
  if (v_venta->>'pagado')::bigint <> 30000 then raise exception 'FALLO: pagado % (se esperaba seña 20000 + 10000)', v_venta->>'pagado'; end if;
  if (select count(*) from pagos where cliente_id = c1 and not anulado) <> 2 then raise exception 'FALLO: se esperaban 2 pagos (seña y cobro)'; end if;
  v_ok := v_ok || 'entrega repetida = una venta, una factura, un cobro'::text;

  -- ---------- No se cobra de más ----------
  begin
    perform registrar_pago(gen_random_uuid(), c1, 999999, 'efectivo', null, null, null, null);
    raise exception 'FALLO: dejó cobrar más de lo que debe';
  exception when others then
    if sqlerrm like 'FALLO%' then raise; end if;
  end;
  v_ok := v_ok || 'no cobra de más'::text;

  -- ---------- Si falla, la clave no queda tomada ----------
  begin
    perform registrar_pago(k_mal, c2, 5000, 'efectivo', null, null, null, null);
    raise exception 'FALLO: cobró a un local que no debe';
  exception when others then
    if sqlerrm like 'FALLO%' then raise; end if;
  end;
  if exists (select 1 from operaciones where clave = k_mal) then raise exception 'FALLO: la clave de una operación fallida quedó reservada'; end if;
  v_ok := v_ok || 'clave libre después de un fallo'::text;

  -- ---------- La misma clave no sirve para otra operación ----------
  begin
    perform anular_pedido(k_p1, (p1->>'id')::uuid, 'Prueba');
    raise exception 'FALLO: aceptó una clave usada para otra operación';
  exception when others then
    if sqlerrm like 'FALLO%' then raise; end if;
  end;
  v_ok := v_ok || 'clave de otra operación rechazada'::text;

  -- ---------- El vendedor no ve costos ni puede operar lo del administrador ----------
  insert into auth.users (id, email, aud, role) values (v_vend, 'zz.prueba@usuarios.sistema-pedidos.invalid', 'authenticated', 'authenticated');
  insert into miembros (user_id, nombre, usuario, rol) values (v_vend, 'ZZ Vendedor Prueba', 'zz.prueba', 'vendedor');
  perform set_config('request.jwt.claims', json_build_object('sub', v_vend, 'role', 'authenticated')::text, true);
  if exists (select 1 from jsonb_array_elements(obtener_pedido((p1->>'id')::uuid)->'lineas') e where e ? 'costo') then
    raise exception 'FALLO: el vendedor ve el costo de las líneas';
  end if;
  if exists (select 1 from jsonb_array_elements(listar_productos(true)) e where e ? 'precio_compra' or e ? 'costo_promedio') then
    raise exception 'FALLO: el vendedor ve el precio de compra';
  end if;
  begin
    perform registrar_gasto(gen_random_uuid(), 'Combustible', 50000, null, null, null);
    raise exception 'FALLO: el vendedor pudo cargar un gasto';
  exception when others then
    if sqlerrm like 'FALLO%' then raise; end if;
  end;
  v_ok := v_ok || 'vendedor sin costos ni permisos de administrador'::text;

  -- Números de documento como estaban.
  for v_seq in select key as n, value as v from jsonb_each(v_seqs) loop
    if v_seq.v = 'null'::jsonb then
      perform setval('public.' || v_seq.n, 1, false);
    else
      perform setval('public.' || v_seq.n, (v_seq.v)::text::bigint, true);
    end if;
  end loop;

  raise exception 'PRUEBA OK (% pruebas): %', cardinality(v_ok), array_to_string(v_ok, ' · ');
exception when others then
  -- Si falló en el medio, igual se dejan los números como estaban.
  for v_seq in select key as n, value as v from jsonb_each(v_seqs) loop
    if v_seq.v = 'null'::jsonb then
      perform setval('public.' || v_seq.n, 1, false);
    else
      perform setval('public.' || v_seq.n, (v_seq.v)::text::bigint, true);
    end if;
  end loop;
  raise;
end $prueba$;
