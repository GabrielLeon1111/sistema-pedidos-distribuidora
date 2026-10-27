-- La pantalla de ingreso ofrece "crear el administrador" solo si todavía no hay ninguno.
-- Se agrega al encabezado un sí/no (tiene_admin), sin ningún dato de los usuarios.
create or replace function public.encabezado_negocio() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('nombre', nombre, 'rubro', rubro, 'propietario', propietario, 'actividades', actividades,
    'direccion', direccion, 'ciudad', ciudad, 'telefono', telefono,
    'tiene_admin', exists (select 1 from miembros where rol = 'admin' and activo))
  from negocio where id = 'negocio';
$$;
