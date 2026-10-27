import 'json.dart';

class LineaCompra {
  final String productoId;
  final String descripcion;
  final String unidad;
  final double cantidad;
  final int costo;

  const LineaCompra({required this.productoId, required this.descripcion, required this.unidad, required this.cantidad, required this.costo});

  int get total => (cantidad * costo).round();

  factory LineaCompra.fromMap(Map<String, dynamic> m) => LineaCompra(
        productoId: m['producto_id'] as String,
        descripcion: m['descripcion'] as String,
        unidad: (m['unidad'] as String?) ?? 'unidad',
        cantidad: toDouble(m['cantidad']),
        costo: toInt(m['costo']),
      );

  Map<String, dynamic> toMap() =>
      {'producto_id': productoId, 'descripcion': descripcion, 'unidad': unidad, 'cantidad': cantidad, 'costo': costo};
}

/// Compra propia para tener mercadería en stock (fuera de los pedidos).
class Compra {
  final String id;
  final int numero;
  final DateTime fecha;
  final String? proveedorId;
  final String proveedorNombre;
  final String? factura;
  final List<LineaCompra> lineas;
  final String? registradoPor;

  const Compra({
    required this.id,
    required this.numero,
    required this.fecha,
    this.proveedorId,
    required this.proveedorNombre,
    this.factura,
    required this.lineas,
    this.registradoPor,
  });

  int get total => lineas.fold(0, (s, l) => s + l.total);

  factory Compra.fromMap(Map<String, dynamic> m) => Compra(
        id: m['id'] as String,
        numero: toInt(m['numero']),
        fecha: toDate(m['fecha']),
        proveedorId: m['proveedor_id'] as String?,
        proveedorNombre: m['proveedor_nombre'] as String,
        factura: textOrNull(m['factura']),
        lineas: [for (final l in toMapList(m['lineas'])) LineaCompra.fromMap(l)],
        registradoPor: m['registrado_por'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'numero': numero,
        'fecha': fecha.toIso8601String(),
        'proveedor_id': proveedorId,
        'proveedor_nombre': proveedorNombre,
        'factura': factura,
        'lineas': [for (final l in lineas) l.toMap()],
        'registrado_por': registradoPor,
      };
}
