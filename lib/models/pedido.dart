import 'cliente.dart';
import 'json.dart';
import 'linea.dart';

/// En qué paso está la nota de pedido.
enum EstadoPedido {
  /// Cargado en el local; todavía se puede editar.
  cargado('cargado', 'Cargado'),

  /// Ya está en un consolidado (pedido al proveedor).
  pedido('pedido', 'Pedido al proveedor'),

  /// Llegó la mercadería: listo para entregar.
  recibido('recibido', 'Listo para entregar'),

  /// El local no estaba: queda pendiente con nueva fecha.
  pendiente('pendiente', 'Entrega pendiente'),
  entregado('entregado', 'Entregado'),

  /// El local no recibió nada.
  rechazado('rechazado', 'Rechazado'),
  anulado('anulado', 'Anulado');

  const EstadoPedido(this.valor, this.texto);
  final String valor;
  final String texto;

  static EstadoPedido de(String? v) => values.firstWhere((e) => e.valor == v, orElse: () => cargado);
}

class Pedido {
  final String id;
  final int numero;
  final DateTime fecha;
  final String clienteId;
  final DatosCliente cliente;
  final String? vendedorId;
  final String? vendedorNombre;
  final List<Linea> lineas;
  final String? observaciones;
  final EstadoPedido estado;

  /// Fecha prevista de entrega (cambia si el local no estaba).
  final DateTime? fechaEntrega;
  final String? consolidadoId;
  final String? ventaId;

  /// Motivo de anulación o de rechazo.
  final String? motivo;
  final DateTime? actualizado;

  const Pedido({
    required this.id,
    required this.numero,
    required this.fecha,
    required this.clienteId,
    required this.cliente,
    this.vendedorId,
    this.vendedorNombre,
    required this.lineas,
    this.observaciones,
    this.estado = EstadoPedido.cargado,
    this.fechaEntrega,
    this.consolidadoId,
    this.ventaId,
    this.motivo,
    this.actualizado,
    this.sinSincronizar = false,
    this.errorSincronizacion,
  });

  /// Se levantó sin señal y todavía no se subió (solo existe en este teléfono).
  final bool sinSincronizar;

  /// Por qué no se pudo subir (el servidor la rechazó), para que se corrija.
  final String? errorSincronizacion;

  /// Total con lo que realmente se entrega (ya ajustado por lo que no llegó).
  int get total => sumaTotales(lineas);

  /// Total de lo que pidió el local.
  int get totalPedido => lineas.fold(0, (s, l) => s + l.totalPedido);

  bool get editable => estado == EstadoPedido.cargado;
  bool get esperandoConfirmacion => lineas.any((l) => l.esperandoConfirmacion);
  bool get todoDeStock => lineas.isNotEmpty && lineas.every((l) => l.deStock);

  /// Lo que hay que pedir al proveedor (lo que no sale del stock).
  Iterable<Linea> get lineasAProveedor => lineas.where((l) => !l.deStock);

  /// Se puede entregar: llegó la mercadería (o todo sale del stock) y no hay
  /// líneas esperando que el local confirme.
  bool get entregable =>
      !esperandoConfirmacion &&
      (estado == EstadoPedido.recibido ||
          estado == EstadoPedido.pendiente ||
          (estado == EstadoPedido.cargado && todoDeStock));

  bool get cerrado => estado == EstadoPedido.entregado || estado == EstadoPedido.rechazado || estado == EstadoPedido.anulado;

  factory Pedido.fromMap(Map<String, dynamic> m) => Pedido(
        id: m['id'] as String,
        numero: toInt(m['numero']),
        fecha: toDate(m['fecha']),
        clienteId: m['cliente_id'] as String,
        cliente: DatosCliente.fromMap(m['cliente'] as Map<String, dynamic>?),
        vendedorId: m['vendedor_id'] as String?,
        vendedorNombre: m['vendedor_nombre'] as String?,
        lineas: [for (final l in toMapList(m['lineas'])) Linea.fromMap(l)],
        observaciones: textOrNull(m['observaciones']),
        estado: EstadoPedido.de(m['estado'] as String?),
        fechaEntrega: toDateOrNull(m['fecha_entrega']),
        consolidadoId: m['consolidado_id'] as String?,
        ventaId: m['venta_id'] as String?,
        motivo: textOrNull(m['motivo']),
        actualizado: toDateOrNull(m['actualizado']),
        sinSincronizar: m['sin_sincronizar'] == true,
        errorSincronizacion: textOrNull(m['error_sincronizacion']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'numero': numero,
        'fecha': fecha.toIso8601String(),
        'cliente_id': clienteId,
        'cliente': cliente.toMap(),
        'vendedor_id': vendedorId,
        'vendedor_nombre': vendedorNombre,
        'lineas': [for (final l in lineas) l.toMap()],
        'observaciones': observaciones,
        'estado': estado.valor,
        'fecha_entrega': fechaEntrega?.toIso8601String(),
        'consolidado_id': consolidadoId,
        'venta_id': ventaId,
        'motivo': motivo,
        'actualizado': actualizado?.toIso8601String(),
      };

  Pedido copyWith({
    List<Linea>? lineas,
    EstadoPedido? estado,
    DateTime? fechaEntrega,
    String? consolidadoId,
    String? ventaId,
    String? motivo,
    String? observaciones,
    DatosCliente? cliente,
    String? clienteId,
  }) =>
      Pedido(
        id: id,
        numero: numero,
        fecha: fecha,
        clienteId: clienteId ?? this.clienteId,
        cliente: cliente ?? this.cliente,
        vendedorId: vendedorId,
        vendedorNombre: vendedorNombre,
        lineas: lineas ?? this.lineas,
        observaciones: observaciones ?? this.observaciones,
        estado: estado ?? this.estado,
        fechaEntrega: fechaEntrega ?? this.fechaEntrega,
        consolidadoId: consolidadoId ?? this.consolidadoId,
        ventaId: ventaId ?? this.ventaId,
        motivo: motivo ?? this.motivo,
        actualizado: DateTime.now(),
        sinSincronizar: sinSincronizar,
        errorSincronizacion: errorSincronizacion,
      );

  /// Sin costos (para el vendedor).
  Pedido sinCostos() => copyWith(lineas: [for (final l in lineas) l.sinCosto()]);
}
