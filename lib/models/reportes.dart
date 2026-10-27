import 'ganancia.dart';

/// Ventas y ganancia de un período.
class Periodo {
  final int vendido;
  final int ganancia;
  final int notas;
  const Periodo({this.vendido = 0, this.ganancia = 0, this.notas = 0});
}

class ProductoRanking {
  final String nombre;
  final String unidad;
  final double cantidad;
  final int vendido;
  final int ganancia;
  const ProductoRanking({required this.nombre, required this.unidad, required this.cantidad, required this.vendido, required this.ganancia});

  /// Margen sobre el costo (como en el presupuesto: 50.000 → 60.000 = 20 %).
  double? get margen {
    final costo = vendido - ganancia;
    return costo <= 0 ? null : ganancia * 100 / costo;
  }
}

class Avisos {
  final int esperandoConfirmacion;
  final int sinEntregar;
  final int entregasAtrasadas;
  final int sinRecibir;
  final int sinPedir;
  final int stockBajo;
  const Avisos({
    this.esperandoConfirmacion = 0,
    this.sinEntregar = 0,
    this.entregasAtrasadas = 0,
    this.sinRecibir = 0,
    this.sinPedir = 0,
    this.stockBajo = 0,
  });

  bool get hayAlgo => esperandoConfirmacion + sinEntregar + sinRecibir + sinPedir + stockBajo > 0;
}

/// Lo que muestra Inicio.
class Panel {
  final Periodo hoy;
  final Periodo semana;
  final Periodo mes;
  final Periodo anio;

  /// Mismo tramo del mes anterior (del 1 al mismo día), para comparar parejo.
  final Periodo mesAnterior;
  final int cobradoHoy;
  final int totalDeuda;
  final int localesQueDeben;
  final List<ProductoRanking> masVendidos;
  final List<ProductoRanking> masGanancia;
  final Avisos avisos;

  /// Vendido por mes (últimos 12), del más viejo al actual.
  final List<(DateTime, int)> meses;

  /// Lo que se ganaría si se venden todas las notas de pedido sin entregar.
  final EstimacionGanancia pendiente;
  final int notasPendientes;

  /// Lo que suman las notas de pedido sin entregar (lo que se cobraría, sin descontar nada).
  final int totalPendiente;

  const Panel({
    required this.hoy,
    required this.semana,
    required this.mes,
    required this.anio,
    required this.mesAnterior,
    required this.cobradoHoy,
    required this.totalDeuda,
    required this.localesQueDeben,
    required this.masVendidos,
    required this.masGanancia,
    required this.avisos,
    required this.meses,
    required this.pendiente,
    required this.notasPendientes,
    required this.totalPendiente,
  });

  /// Variación del mes contra el mes anterior, en %.
  double? get variacionMes => mesAnterior.vendido <= 0 ? null : (mes.vendido - mesAnterior.vendido) * 100 / mesAnterior.vendido;
}

class FilaLocal {
  final String nombre;
  final int vendido;
  final int ganancia;
  final int cobrado;
  final int saldo;
  final int rechazos;
  const FilaLocal({required this.nombre, required this.vendido, required this.ganancia, required this.cobrado, required this.saldo, required this.rechazos});

  double? get margen {
    final costo = vendido - ganancia;
    return costo <= 0 ? null : ganancia * 100 / costo;
  }
}

class GastoCategoria {
  final String categoria;
  final int cantidad;
  final int monto;
  const GastoCategoria(this.categoria, this.cantidad, this.monto);
}

/// Reporte de un período (día, semana, mes o rango).
class Reporte {
  final DateTime desde;
  final DateTime hasta;
  final int vendido;
  final int costoVendido;
  final int notas;

  /// Lo que se le pagó al proveedor (recepciones) y las compras propias.
  final int pagadoProveedor;
  final int comprasPropias;
  final int gastos;
  final List<GastoCategoria> gastosPorCategoria;

  /// Mercadería perdida (a costo).
  final int perdidas;
  final int cobrado;

  /// Lo que todavía deben de las notas del período.
  final int faltaCobrar;

  /// Pedidos (o productos) que los locales no recibieron: valor de venta perdido.
  final int perdidoRechazos;
  final int cantidadRechazos;
  final int descuentos;
  final List<ProductoRanking> productos;
  final List<FilaLocal> locales;

  const Reporte({
    required this.desde,
    required this.hasta,
    required this.vendido,
    required this.costoVendido,
    required this.notas,
    required this.pagadoProveedor,
    required this.comprasPropias,
    required this.gastos,
    required this.gastosPorCategoria,
    required this.perdidas,
    required this.cobrado,
    required this.faltaCobrar,
    required this.perdidoRechazos,
    required this.cantidadRechazos,
    required this.descuentos,
    required this.productos,
    required this.locales,
  });

  int get ganancia => vendido - costoVendido;

  /// Ganancia real = ganancia de ventas − gastos − pérdidas.
  int get gananciaReal => ganancia - gastos - perdidas;
  double? get margen => costoVendido <= 0 ? null : ganancia * 100 / costoVendido;
  int get totalPagadoProveedores => pagadoProveedor + comprasPropias;
}
