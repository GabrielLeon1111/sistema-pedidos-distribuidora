import 'json.dart';

/// A qué nota de venta se aplicó (parte de) un pago.
class Aplicacion {
  final String ventaId;
  final int ventaNumero;
  final int monto;

  const Aplicacion({required this.ventaId, required this.ventaNumero, required this.monto});

  factory Aplicacion.fromMap(Map<String, dynamic> m) =>
      Aplicacion(ventaId: m['venta_id'] as String, ventaNumero: toInt(m['venta_numero']), monto: toInt(m['monto']));

  Map<String, dynamic> toMap() => {'venta_id': ventaId, 'venta_numero': ventaNumero, 'monto': monto};
}

/// Un pago que hizo un local (la app no cobra: solo lo registra).
/// Se aplica a las notas de venta más viejas primero. Si es una seña de un
/// pedido que todavía no se entregó, queda "a favor" hasta que se entrega.
class Pago {
  final String id;

  /// Número del recibo.
  final int numero;
  final DateTime fecha;
  final String clienteId;
  final String clienteNombre;
  final int monto;
  final String metodo;
  final String? nota;

  /// Seña o adelanto de este pedido.
  final String? pedidoId;
  final int? pedidoNumero;
  final List<Aplicacion> aplicaciones;
  final String? registradoPor;
  final bool anulado;
  final String? motivoAnulacion;

  const Pago({
    required this.id,
    required this.numero,
    required this.fecha,
    required this.clienteId,
    required this.clienteNombre,
    required this.monto,
    required this.metodo,
    this.nota,
    this.pedidoId,
    this.pedidoNumero,
    this.aplicaciones = const [],
    this.registradoPor,
    this.anulado = false,
    this.motivoAnulacion,
  });

  int get aplicado => aplicaciones.fold(0, (s, a) => s + a.monto);

  /// Lo que todavía no se aplicó a ninguna nota (seña o pago de más).
  int get aFavor => anulado ? 0 : monto - aplicado;
  bool get esSena => pedidoId != null;

  factory Pago.fromMap(Map<String, dynamic> m) => Pago(
        id: m['id'] as String,
        numero: toInt(m['numero']),
        fecha: toDate(m['fecha']),
        clienteId: m['cliente_id'] as String,
        clienteNombre: m['cliente_nombre'] as String,
        monto: toInt(m['monto']),
        metodo: (m['metodo'] as String?) ?? 'efectivo',
        nota: textOrNull(m['nota']),
        pedidoId: m['pedido_id'] as String?,
        pedidoNumero: m['pedido_numero'] == null ? null : toInt(m['pedido_numero']),
        aplicaciones: [for (final a in toMapList(m['aplicaciones'])) Aplicacion.fromMap(a)],
        registradoPor: m['registrado_por'] as String?,
        anulado: toBool(m['anulado']),
        motivoAnulacion: textOrNull(m['motivo_anulacion']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'numero': numero,
        'fecha': fecha.toIso8601String(),
        'cliente_id': clienteId,
        'cliente_nombre': clienteNombre,
        'monto': monto,
        'metodo': metodo,
        'nota': nota,
        'pedido_id': pedidoId,
        'pedido_numero': pedidoNumero,
        'aplicaciones': [for (final a in aplicaciones) a.toMap()],
        'registrado_por': registradoPor,
        'anulado': anulado,
        'motivo_anulacion': motivoAnulacion,
      };

  Pago copyWith({List<Aplicacion>? aplicaciones, bool? anulado, String? motivoAnulacion}) => Pago(
        id: id,
        numero: numero,
        fecha: fecha,
        clienteId: clienteId,
        clienteNombre: clienteNombre,
        monto: monto,
        metodo: metodo,
        nota: nota,
        pedidoId: pedidoId,
        pedidoNumero: pedidoNumero,
        aplicaciones: aplicaciones ?? this.aplicaciones,
        registradoPor: registradoPor,
        anulado: anulado ?? this.anulado,
        motivoAnulacion: motivoAnulacion ?? this.motivoAnulacion,
      );
}

const metodosPago = ['efectivo', 'transferencia'];
