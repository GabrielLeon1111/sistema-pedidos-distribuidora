import 'dart:convert';
import 'dart:typed_data';
import 'json.dart';

/// Datos del negocio que salen en las notas de pedido, notas de venta y recibos.
class Negocio {
  final String nombre;
  final String rubro;

  /// Dueño (sale en la factura: "de Juan Carlos Benítez").
  final String? propietario;

  /// Actividades económicas (salen en la factura debajo del nombre).
  final String? actividades;
  final String? ruc;
  final String? telefono;
  final String? direccion;
  final String? ciudad;
  final String? email;

  /// Logo en PNG/JPG (base64). Con Supabase pasa a Storage.
  final String? logoBase64;

  /// Nota al pie de las notas y recibos.
  final String? notaPie;

  const Negocio({
    this.nombre = 'Mi Negocio',
    this.rubro = 'Venta por catálogo',
    this.propietario,
    this.actividades,
    this.ruc,
    this.telefono,
    this.direccion,
    this.ciudad,
    this.email,
    this.logoBase64,
    this.notaPie,
  });

  Uint8List? get logo {
    final b = logoBase64;
    if (b == null || b.isEmpty) return null;
    try {
      return base64Decode(b);
    } catch (_) {
      return null;
    }
  }

  factory Negocio.fromMap(Map<String, dynamic> m) => Negocio(
        nombre: textOrNull(m['nombre']) ?? 'Mi Negocio',
        rubro: textOrNull(m['rubro']) ?? 'Venta por catálogo',
        propietario: textOrNull(m['propietario']),
        actividades: textOrNull(m['actividades']),
        ruc: textOrNull(m['ruc']),
        telefono: textOrNull(m['telefono']),
        direccion: textOrNull(m['direccion']),
        ciudad: textOrNull(m['ciudad']),
        email: textOrNull(m['email']),
        logoBase64: textOrNull(m['logo_base64']),
        notaPie: textOrNull(m['nota_pie']),
      );

  Map<String, dynamic> toMap() => {
        'id': 'negocio',
        'nombre': nombre.trim(),
        'rubro': rubro.trim(),
        'propietario': textOrNull(propietario),
        'actividades': textOrNull(actividades),
        'ruc': textOrNull(ruc),
        'telefono': textOrNull(telefono),
        'direccion': textOrNull(direccion),
        'ciudad': textOrNull(ciudad),
        'email': textOrNull(email),
        'logo_base64': logoBase64,
        'nota_pie': textOrNull(notaPie),
      };

  /// Línea de datos para el pie de los documentos.
  String get lineaDatos => [
        nombre,
        if (ruc != null) 'RUC $ruc',
        if (telefono != null) 'Tel. $telefono',
        ?direccion,
        ?ciudad,
      ].join(' · ');
}
