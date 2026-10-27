import 'linea.dart';
import 'producto.dart';

/// Lo que se ganaría si se vende toda la nota: lo que se cobra menos lo que
/// cuesta cada producto. El costo es el que ya tiene la línea (cuando llegó o
/// sale del stock) o, si no, el último precio de compra del producto.
/// Solo lo ve el administrador: nunca sale en la nota ni en el PDF.
class EstimacionGanancia {
  const EstimacionGanancia({required this.venta, required this.costo, required this.sinCosto});

  final int venta;
  final int costo;

  /// Productos sin precio de compra (su ganancia no se puede calcular).
  final List<String> sinCosto;

  int get ganancia => venta - costo;
  double? get margen => costo <= 0 ? null : ganancia * 100 / costo;

  factory EstimacionGanancia.de(Iterable<Linea> lineas, List<Producto> productos, {Map<String, int> costos = const {}}) {
    var venta = 0;
    var costo = 0;
    final sin = <String>[];
    for (final l in lineas) {
      if (l.cantidadEfectiva <= 0) continue;
      final prod = productos.where((p) => p.id == l.productoId).firstOrNull;
      final c = costos[l.id] ?? (l.costo > 0 ? l.costo : ((prod?.costoReferencia ?? 0) * l.factor).round());
      if (c <= 0) {
        sin.add(l.descripcion);
        continue;
      }
      venta += l.total;
      costo += (l.cantidadEfectiva * c).round();
    }
    return EstimacionGanancia(venta: venta, costo: costo, sinCosto: sin);
  }
}
