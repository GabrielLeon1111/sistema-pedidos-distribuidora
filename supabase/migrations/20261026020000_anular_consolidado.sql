-- =================================================================
--  ANULAR UN PEDIDO AL PROVEEDOR (consolidado)
--  Mientras la mercadería no llegó, el administrador puede anular la hoja
--  que le mandó al proveedor: las notas de pedido vuelven a "cargado" (se
--  pueden editar, anular o volver a pedir) y la hoja queda anulada, con el
--  motivo, para el historial. Una hoja ya recibida no se anula.
-- =================================================================
alter table public.consolidados drop constraint consolidados_estado_check;
alter table public.consolidados add constraint consolidados_estado_check check (estado in ('enviado', 'recibido', 'anulado'));
alter table public.consolidados add column motivo text, add column anulado_por text, add column fecha_anulacion timestamptz;

create function public.anular_consolidado_sin_clave(p_id uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_u miembros := assert_admin();
  v_m text := limpiar(p_motivo);
  v_c consolidados;
  v_otro consolidados;
  v_p pedidos;
begin
  if v_m is null or char_length(v_m) < 3 then raise exception 'Escribí el motivo.'; end if;
  select * into v_c from consolidados where id = p_id for update;
  if not found then raise exception 'El pedido al proveedor ya no existe.'; end if;
  if v_c.estado = 'recibido' then raise exception 'Esta mercadería ya se recibió: no se puede anular.'; end if;
  if v_c.estado = 'anulado' then raise exception 'Este pedido al proveedor ya está anulado.'; end if;
  perform 1 from pedidos where id = any(v_c.pedido_ids) for update;

  -- Si una nota también tiene productos de otro proveedor, se anulan juntas.
  select * into v_otro from consolidados o
  where o.id <> v_c.id and o.estado <> 'anulado' and o.pedido_ids && v_c.pedido_ids
  order by o.numero limit 1;
  if found then
    raise exception 'La nota también está en el pedido N° % a %. Anulá ese primero (o registrá su recepción).',
      nro(v_otro.numero), v_otro.proveedor_nombre;
  end if;

  for v_p in select * from pedidos where id = any(v_c.pedido_ids) loop
    if v_p.estado <> 'pedido' then
      raise exception 'El pedido N° % ya no está esperando al proveedor.', nro(v_p.numero);
    end if;
  end loop;
  update pedidos set estado = 'cargado', consolidado_id = null, actualizado = now() where id = any(v_c.pedido_ids);
  update consolidados set estado = 'anulado', motivo = v_m, anulado_por = v_u.nombre, fecha_anulacion = now()
  where id = v_c.id returning * into v_c;
  perform auditar('Proveedor', 'Anuló pedido al proveedor', 'N° ' || nro(v_c.numero) || ' a ' || v_c.proveedor_nombre ||
    ' · ' || cardinality(v_c.pedido_ids) || ' notas vuelven a cargadas · Motivo: ' || v_m, true);
  return to_jsonb(v_c);
end $$;

create function public.anular_consolidado(p_clave uuid, p_id uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_prev jsonb := reservar_clave(p_clave, 'anular_consolidado');
begin
  if v_prev is not null then return v_prev; end if;
  return guardar_resultado(p_clave, anular_consolidado_sin_clave(p_id, p_motivo));
end $$;

revoke execute on function public.anular_consolidado_sin_clave(uuid, text) from public, anon, authenticated;
revoke execute on function public.anular_consolidado(uuid, uuid, text) from public, anon;
grant execute on function public.anular_consolidado(uuid, uuid, text) to authenticated;

-- Una hoja anulada no se toca más (por ejemplo, no se le registra la recepción).
create function public.consolidado_anulado_fijo() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if old.estado = 'anulado' then raise exception 'Este pedido al proveedor está anulado.'; end if;
  return new;
end $$;
create trigger consolidado_anulado_fijo before update on public.consolidados
for each row execute function public.consolidado_anulado_fijo();
