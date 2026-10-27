import 'json.dart';

/// Persona que usa la app. Administrador: todo. Vendedor: solo pedidos y
/// clientes, sin ver costos ni márgenes.
class Usuario {
  final String id;
  final String nombre;

  /// Con lo que ingresa (ej: "juan.perez").
  final String usuario;
  final String rol;
  final bool activo;
  final DateTime creado;

  const Usuario({
    required this.id,
    required this.nombre,
    required this.usuario,
    required this.rol,
    this.activo = true,
    required this.creado,
  });

  bool get esAdmin => rol == 'admin';
  String get rolTexto => esAdmin ? 'Administrador' : 'Vendedor';

  factory Usuario.fromMap(Map<String, dynamic> m) => Usuario(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        usuario: m['usuario'] as String,
        rol: (m['rol'] as String?) ?? 'vendedor',
        activo: m['activo'] != false,
        creado: toDate(m['creado']),
      );
}
