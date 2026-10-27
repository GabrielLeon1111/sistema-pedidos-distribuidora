-- =================================================================
--  ENCABEZADO DEL NEGOCIO PARA LA PANTALLA DE INGRESO
--  Antes de iniciar sesión la app muestra el encabezado igual que en la
--  factura. Solo devuelve lo que ya sale impreso en cada factura (nombre,
--  propietario, actividades, dirección, ciudad y teléfono): ni RUC, ni email,
--  ni logo, ni nada más de la tabla.
-- =================================================================
create or replace function public.encabezado_negocio() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('nombre', nombre, 'rubro', rubro, 'propietario', propietario, 'actividades', actividades,
    'direccion', direccion, 'ciudad', ciudad, 'telefono', telefono)
  from negocio where id = 'negocio';
$$;

revoke execute on function public.encabezado_negocio() from public;
grant execute on function public.encabezado_negocio() to anon, authenticated;
