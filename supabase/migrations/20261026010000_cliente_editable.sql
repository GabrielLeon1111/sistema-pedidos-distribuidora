-- =================================================================
--  EDITAR UN LOCAL ACTUALIZA SUS PEDIDOS SIN ENTREGAR
--  Cada nota de pedido guarda una copia de los datos del local. Si después
--  se completan (RUC, razón social, dirección...), las notas que todavía no
--  se entregaron toman los datos nuevos: así la factura sale completa.
--  Las notas ya entregadas, anuladas o rechazadas quedan como se emitieron.
-- =================================================================
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
  if v_existe then
    update pedidos set cliente = jsonb_build_object('nombre', v_c.nombre, 'razon_social', v_c.razon_social, 'ruc', v_c.ruc,
        'direccion', v_c.direccion, 'telefono', v_c.telefono, 'contacto', v_c.contacto)
    where cliente_id = v_c.id and estado not in ('entregado', 'anulado', 'rechazado');
  end if;
  perform auditar('Clientes', case when v_existe then 'Editó local' else 'Nuevo local' end, v_nombre);
  return to_jsonb(v_c);
end $$;
