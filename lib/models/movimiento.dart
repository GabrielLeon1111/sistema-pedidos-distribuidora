import 'json.dart';

/// Tipos de entrada y salida de stock.
enum TipoMovimiento {
  sobrantePedido('sobrante_pedido', 'Sobrante de pedido', true),
  compra('compra', 'Compra', true),
  venta('venta', 'Venta', false),
  devolucionProveedor('devolucion_proveedor', 'Devolución al proveedor', false),
  perdida('perdida', 'Pérdida', false),
  ajuste('ajuste', 'Ajuste', true),
  anulacion('anulacion', 'Anulación de venta', true);

  const TipoMovimiento(this.valor, this.texto, this.entrada);
  final String valor;
  final String texto;
  final bool entrada;

  static TipoMovimiento de(String? v) => values.firstWhere((e) => e.valor == v, orElse: () => ajuste);
}

class Movimiento {
  final String id;
  final DateTime fecha;
  final String productoId;
  final String productoNombre;
  final TipoMovimiento tipo;

  /// Positiva si entra, negativa si sale.
  final double cantidad;
  final int costoUnitario;
  final double stockResultante;
  final String? motivo;

  /// Ej: "Pedido N° 000012"
  final String? referencia;
  final String? usuarioNombre;

  const Movimiento({
    required this.id,
    required this.fecha,
    required this.productoId,
    required this.productoNombre,
    required this.tipo,
    required this.cantidad,
    this.costoUnitario = 0,
    required this.stockResultante,
    this.motivo,
    this.referencia,
    this.usuarioNombre,
  });

  int get valor => (cantidad.abs() * costoUnitario).round();

  factory Movimiento.fromMap(Map<String, dynamic> m) => Movimiento(
        id: m['id'] as String,
        fecha: toDate(m['fecha']),
        productoId: m['producto_id'] as String,
        productoNombre: m['producto_nombre'] as String,
        tipo: TipoMovimiento.de(m['tipo'] as String?),
        cantidad: toDouble(m['cantidad']),
        costoUnitario: toInt(m['costo_unitario']),
        stockResultante: toDouble(m['stock_resultante']),
        motivo: textOrNull(m['motivo']),
        referencia: textOrNull(m['referencia']),
        usuarioNombre: m['usuario_nombre'] as String?,
      );
}
