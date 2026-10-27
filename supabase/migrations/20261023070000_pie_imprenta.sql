-- =================================================================
--  PIE DE LA FACTURA: datos de la imprenta de cada timbrado
--  (habilitación, imprenta, RUC, talonarios, rango y fecha).
--  Cada factura guarda una copia para reimprimirse igual.
-- =================================================================

alter table public.timbrados add column pie_imprenta text check (char_length(pie_imprenta) <= 300);
alter table public.ventas add column factura_pie text;

create or replace function public.emitir_factura(p_venta uuid, p_remision text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_t timbrados;
  v_hoy date := (now() at time zone 'America/Asuncion')::date;
begin
  select * into v_t from timbrados
  where activo and v_hoy between inicio and fin and siguiente <= hasta
  for update;
  if not found then raise exception 'No hay un timbrado vigente para facturar. Cargalo en Más → Timbrado.'; end if;
  update timbrados set siguiente = siguiente + 1 where id = v_t.id;
  update ventas set timbrado_id = v_t.id, timbrado_numero = v_t.numero, timbrado_inicio = v_t.inicio, timbrado_fin = v_t.fin,
    establecimiento = v_t.establecimiento, punto = v_t.punto, factura_numero = v_t.siguiente, condicion = 'credito',
    nota_remision = limpiar(p_remision), factura_pie = v_t.pie_imprenta
  where id = p_venta;
end $$;

create or replace function public.guardar_timbrado(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id uuid := coalesce((p->>'id')::uuid, gen_random_uuid());
  v_antes timbrados;
  v_r timbrados;
  v_num text := p->>'numero';
  v_est text := coalesce(p->>'establecimiento', '001');
  v_pto text := coalesce(p->>'punto', '001');
  v_sig integer := (p->>'siguiente')::integer;
  v_activo boolean := coalesce((p->>'activo')::boolean, true);
  v_pie text := limpiar_multi(p->>'pie_imprenta');
begin
  perform assert_admin();
  if v_num is null or v_num !~ '^[0-9]{8}$' then raise exception 'El número de timbrado tiene 8 dígitos.'; end if;
  if v_est !~ '^[0-9]{3}$' then raise exception 'El establecimiento tiene 3 dígitos (ej: 001).'; end if;
  if v_pto !~ '^[0-9]{3}$' then raise exception 'El punto de expedición tiene 3 dígitos (ej: 001).'; end if;
  if (p->>'fin')::date < (p->>'inicio')::date then raise exception 'La fecha de fin de vigencia tiene que ser después del inicio.'; end if;
  if (p->>'desde')::integer < 1 or (p->>'hasta')::integer > 9999999 or (p->>'hasta')::integer < (p->>'desde')::integer then
    raise exception 'Revisá el rango de numeración (de 1 a 9.999.999).';
  end if;
  if v_sig < (p->>'desde')::integer or v_sig > (p->>'hasta')::integer + 1 then raise exception 'El próximo número tiene que estar dentro del rango.'; end if;
  if char_length(v_pie) > 300 then raise exception 'Los datos de la imprenta son muy largos (máximo 300 caracteres).'; end if;
  select * into v_antes from timbrados where id = v_id for update;
  if found then
    if v_sig < v_antes.siguiente then
      raise exception 'El próximo número no puede bajar: ya se emitió hasta el %.', v_antes.siguiente - 1;
    end if;
    if exists (select 1 from ventas where timbrado_id = v_id)
       and (v_antes.numero <> v_num or v_antes.establecimiento <> v_est or v_antes.punto <> v_pto) then
      raise exception 'Este timbrado ya tiene facturas emitidas: no se puede cambiar el número ni el punto de expedición.';
    end if;
  end if;
  if v_activo then update timbrados set activo = false where activo and id <> v_id; end if;
  insert into timbrados (id, numero, inicio, fin, establecimiento, punto, desde, hasta, siguiente, activo, pie_imprenta)
  values (v_id, v_num, (p->>'inicio')::date, (p->>'fin')::date, v_est, v_pto, (p->>'desde')::integer, (p->>'hasta')::integer, v_sig, v_activo, v_pie)
  on conflict (id) do update set numero = excluded.numero, inicio = excluded.inicio, fin = excluded.fin,
    establecimiento = excluded.establecimiento, punto = excluded.punto, desde = excluded.desde, hasta = excluded.hasta,
    siguiente = excluded.siguiente, activo = excluded.activo, pie_imprenta = excluded.pie_imprenta
  returning * into v_r;
  perform auditar('Negocio', case when v_antes.id is null then 'Nuevo timbrado' else 'Editó timbrado' end,
    'Timbrado N° ' || v_r.numero || ' · ' || v_r.establecimiento || '-' || v_r.punto || ' · vigencia ' ||
    to_char(v_r.inicio, 'DD/MM/YYYY') || ' al ' || to_char(v_r.fin, 'DD/MM/YYYY') || ' · próxima factura ' || v_r.siguiente, true);
  return to_jsonb(v_r);
end $$;
