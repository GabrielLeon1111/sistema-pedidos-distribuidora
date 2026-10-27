import 'json.dart';

/// Un local (cliente) con todo lo necesario para hacerle la factura.
class Cliente {
  final String id;

  /// Nombre del local (ej: "Despensa San Roque").
  final String nombre;
  final String? razonSocial;
  final String? ruc;
  final String? direccion;
  final String? telefono;
  final String? contacto;
  final String? notas;
  final bool activo;
  final DateTime creado;

  const Cliente({
    required this.id,
    required this.nombre,
    this.razonSocial,
    this.ruc,
    this.direccion,
    this.telefono,
    this.contacto,
    this.notas,
    this.activo = true,
    required this.creado,
  });

  factory Cliente.fromMap(Map<String, dynamic> m) => Cliente(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        razonSocial: textOrNull(m['razon_social']),
        ruc: textOrNull(m['ruc']),
        direccion: textOrNull(m['direccion']),
        telefono: textOrNull(m['telefono']),
        contacto: textOrNull(m['contacto']),
        notas: textOrNull(m['notas']),
        activo: m['activo'] != false,
        creado: toDate(m['creado']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre.trim(),
        'razon_social': textOrNull(razonSocial),
        'ruc': textOrNull(ruc),
        'direccion': textOrNull(direccion),
        'telefono': textOrNull(telefono),
        'contacto': textOrNull(contacto),
        'notas': textOrNull(notas),
        'activo': activo,
        'creado': creado.toIso8601String(),
      };

  /// Datos que se copian en cada documento (si después cambia el cliente,
  /// la nota vieja sigue mostrando lo que tenía).
  DatosCliente get datos => DatosCliente(
        nombre: nombre,
        razonSocial: razonSocial,
        ruc: ruc,
        direccion: direccion,
        telefono: telefono,
        contacto: contacto,
      );

  bool coincide(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return true;
    return nombre.toLowerCase().contains(t) ||
        (razonSocial?.toLowerCase().contains(t) ?? false) ||
        (ruc?.contains(t) ?? false) ||
        (contacto?.toLowerCase().contains(t) ?? false);
  }
}

/// Copia de los datos del cliente guardada en el documento.
class DatosCliente {
  final String nombre;
  final String? razonSocial;
  final String? ruc;
  final String? direccion;
  final String? telefono;
  final String? contacto;

  const DatosCliente({required this.nombre, this.razonSocial, this.ruc, this.direccion, this.telefono, this.contacto});

  factory DatosCliente.fromMap(Map<String, dynamic>? m) => DatosCliente(
        nombre: (m?['nombre'] as String?) ?? 'Cliente',
        razonSocial: textOrNull(m?['razon_social']),
        ruc: textOrNull(m?['ruc']),
        direccion: textOrNull(m?['direccion']),
        telefono: textOrNull(m?['telefono']),
        contacto: textOrNull(m?['contacto']),
      );

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'razon_social': razonSocial,
        'ruc': ruc,
        'direccion': direccion,
        'telefono': telefono,
        'contacto': contacto,
      };
}
