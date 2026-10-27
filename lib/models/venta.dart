import 'cliente.dart';
import 'json.dart';
import 'linea.dart';
import 'timbrado.dart';

/// Nota de venta: lo que el local realmente recibió. Sale de un pedido entregado
/// o de una venta directa desde el stock.
class Venta {
  final String id;
  final int numero;
  final DateTime fecha;
  final String clienteId;
  final DatosCliente cliente;
  final String? pedidoId;
  final int? pedidoNumero;
  final String? vendedorNombre;
  final List<Linea> lineas;
  final String? observaciones;

  /// Total cobrable (ya con descuentos).
  final int total;
  final int costoTotal;

  /// Cuánto se pagó (señas, pago al entregar y pagos posteriores).
  final int pagado;

  /// El local recibió solo una parte del pedido.
  final bool entregaParcial;
  final bool anulada;
  final String? motivoAnulacion;

  /// Factura (timbrado, número y condición de venta).
  final DatosFactura? factura;

  const Venta({
    required this.id,
    required this.numero,
    required this.fecha,
    required this.clienteId,
    required this.cliente,
    this.pedidoId,
    this.pedidoNumero,
    this.vendedorNombre,
    required this.lineas,
    this.observaciones,
    required this.total,
    this.costoTotal = 0,
    this.pagado = 0,
    this.entregaParcial = false,
    this.anulada = false,
    this.motivoAnulacion,
    this.factura,
  });

  int get saldo => anulada ? 0 : (total - pagado).clamp(0, total);
  int get ganancia => total - costoTotal;
  bool get esDirecta => pedidoId == null;

  EstadoPago get estadoPago {
    if (anulada) return EstadoPago.anulada;
    if (saldo <= 0) return EstadoPago.pagado;
    if (pagado > 0) return EstadoPago.parcial;
    return EstadoPago.fiado;
  }

  factory Venta.fromMap(Map<String, dynamic> m) => Venta(
        id: m['id'] as String,
        numero: toInt(m['numero']),
        fecha: toDate(m['fecha']),
        clienteId: m['cliente_id'] as String,
        cliente: DatosCliente.fromMap(m['cliente'] as Map<String, dynamic>?),
        pedidoId: m['pedido_id'] as String?,
        pedidoNumero: m['pedido_numero'] == null ? null : toInt(m['pedido_numero']),
        vendedorNombre: m['vendedor_nombre'] as String?,
        lineas: [for (final l in toMapList(m['lineas'])) Linea.fromMap(l)],
        observaciones: textOrNull(m['observaciones']),
        total: toInt(m['total']),
        costoTotal: toInt(m['costo_total']),
        pagado: toInt(m['pagado']),
        entregaParcial: toBool(m['entrega_parcial']),
        anulada: toBool(m['anulada']),
        motivoAnulacion: textOrNull(m['motivo_anulacion']),
        factura: m['factura_numero'] == null ? null : DatosFactura.fromMap(m),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'numero': numero,
        'fecha': fecha.toIso8601String(),
        'cliente_id': clienteId,
        'cliente': cliente.toMap(),
        'pedido_id': pedidoId,
        'pedido_numero': pedidoNumero,
        'vendedor_nombre': vendedorNombre,
        'lineas': [for (final l in lineas) l.toMap()],
        'observaciones': observaciones,
        'total': total,
        'costo_total': costoTotal,
        'pagado': pagado,
        'entrega_parcial': entregaParcial,
        'anulada': anulada,
        'motivo_anulacion': motivoAnulacion,
        ...?factura?.toMap(),
      };

  Venta copyWith({int? pagado, bool? anulada, String? motivoAnulacion, DatosFactura? factura}) => Venta(
        id: id,
        numero: numero,
        fecha: fecha,
        clienteId: clienteId,
        cliente: cliente,
        pedidoId: pedidoId,
        pedidoNumero: pedidoNumero,
        vendedorNombre: vendedorNombre,
        lineas: lineas,
        observaciones: observaciones,
        total: total,
        costoTotal: costoTotal,
        pagado: pagado ?? this.pagado,
        entregaParcial: entregaParcial,
        anulada: anulada ?? this.anulada,
        motivoAnulacion: motivoAnulacion ?? this.motivoAnulacion,
        factura: factura ?? this.factura,
      );
}

/// Datos de la factura guardados en la venta (foto del timbrado al emitirla).
class DatosFactura {
  final String timbradoId;
  final String timbrado;
  final DateTime inicio;
  final DateTime fin;
  final String establecimiento;
  final String punto;
  final int numero;

  /// 'contado' o 'credito'.
  final String condicion;
  final String? notaRemision;

  /// Copia del pie de la imprenta del timbrado al emitirla.
  final String? pieImprenta;

  const DatosFactura({
    required this.timbradoId,
    required this.timbrado,
    required this.inicio,
    required this.fin,
    required this.establecimiento,
    required this.punto,
    required this.numero,
    required this.condicion,
    this.notaRemision,
    this.pieImprenta,
  });

  bool get contado => condicion == 'contado';

  /// "001-001 0001481"
  String get numeroCompleto => '$establecimiento-$punto ${numero.toString().padLeft(7, '0')}';

  factory DatosFactura.fromMap(Map<String, dynamic> m) => DatosFactura(
        timbradoId: m['timbrado_id'] as String,
        timbrado: m['timbrado_numero'] as String,
        inicio: toDate(m['timbrado_inicio']),
        fin: toDate(m['timbrado_fin']),
        establecimiento: m['establecimiento'] as String,
        punto: m['punto'] as String,
        numero: toInt(m['factura_numero']),
        condicion: (m['condicion'] as String?) ?? 'contado',
        notaRemision: textOrNull(m['nota_remision']),
        pieImprenta: textOrNull(m['factura_pie']),
      );

  Map<String, dynamic> toMap() => {
        'timbrado_id': timbradoId,
        'timbrado_numero': timbrado,
        'timbrado_inicio': fechaIsoDia(inicio),
        'timbrado_fin': fechaIsoDia(fin),
        'establecimiento': establecimiento,
        'punto': punto,
        'factura_numero': numero,
        'condicion': condicion,
        'nota_remision': notaRemision,
        'factura_pie': pieImprenta,
      };

  DatosFactura conCondicion(String c) => DatosFactura(
        timbradoId: timbradoId,
        timbrado: timbrado,
        inicio: inicio,
        fin: fin,
        establecimiento: establecimiento,
        punto: punto,
        numero: numero,
        condicion: c,
        notaRemision: notaRemision,
        pieImprenta: pieImprenta,
      );
}

enum EstadoPago {
  pagado('Pagado'),
  parcial('Pago parcial'),
  fiado('Fiado'),
  anulada('Anulada');

  const EstadoPago(this.texto);
  final String texto;
}
