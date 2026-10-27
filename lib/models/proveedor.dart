import 'json.dart';

class Proveedor {
  final String id;
  final String nombre;
  final String? telefono;
  final String? notas;
  final bool activo;

  const Proveedor({required this.id, required this.nombre, this.telefono, this.notas, this.activo = true});

  factory Proveedor.fromMap(Map<String, dynamic> m) => Proveedor(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        telefono: textOrNull(m['telefono']),
        notas: textOrNull(m['notas']),
        activo: m['activo'] != false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre.trim(),
        'telefono': textOrNull(telefono),
        'notas': textOrNull(notas),
        'activo': activo,
      };
}
