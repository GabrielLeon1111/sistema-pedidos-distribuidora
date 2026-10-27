import 'json.dart';

/// Qué pidió cada local de un producto (para el reparto y la recepción).
class DetalleLocal {
  final String pedidoId;
  final int pedidoNumero;
  final String lineaId;
  final String clienteNombre;
  final double cantidad;

  /// Lo que le tocó al recibir (si llegó una parte se reparte).
  final double? asignado;

  /// Detalle de ese local (ej. "1 rubio, 2 negros").
  final String? nota;

  const DetalleLocal({
    required this.pedidoId,
    required this.pedidoNumero,
    required this.lineaId,
    required this.clienteNombre,
    required this.cantidad,
    this.asignado,
    this.nota,
  });

  factory DetalleLocal.fromMap(Map<String, dynamic> m) => DetalleLocal(
        pedidoId: m['pedido_id'] as String,
        pedidoNumero: toInt(m['pedido_numero']),
        lineaId: m['linea_id'] as String,
        clienteNombre: m['cliente_nombre'] as String,
        cantidad: toDouble(m['cantidad']),
        asignado: m['asignado'] == null ? null : toDouble(m['asignado']),
        nota: textOrNull(m['nota']),
      );

  Map<String, dynamic> toMap() => {
        'pedido_id': pedidoId,
        'pedido_numero': pedidoNumero,
        'linea_id': lineaId,
        'cliente_nombre': clienteNombre,
        'cantidad': cantidad,
        'asignado': asignado,
        'nota': nota,
      };
}

enum EstadoRecepcion {
  pendiente('pendiente', 'Sin marcar'),
  completo('completo', 'Llegó completo'),
  parcial('parcial', 'Llegó una parte'),
  noLlego('no_llego', 'No llegó');

  const EstadoRecepcion(this.valor, this.texto);
  final String valor;
  final String texto;

  static EstadoRecepcion de(String? v) => values.firstWhere((e) => e.valor == v, orElse: () => pendiente);
}

/// Un producto en la hoja del proveedor: la suma de lo que pidieron todos los locales.
class LineaConsolidado {
  final String? productoId;
  final String? codigo;
  final String descripcion;
  final String unidad;

  /// Cuántas unidades del stock es cada una (12 si se pidió por docena).
  final double factor;
  final double cantidad;
  final List<DetalleLocal> detalle;

  /// Los detalles de todos los locales juntos (para el proveedor).
  final String? nota;

  // Recepción
  final EstadoRecepcion recepcion;
  final double cantidadRecibida;
  final int precioCompra;

  const LineaConsolidado({
    this.productoId,
    this.codigo,
    required this.descripcion,
    required this.unidad,
    this.factor = 1,
    required this.cantidad,
    required this.detalle,
    this.nota,
    this.recepcion = EstadoRecepcion.pendiente,
    this.cantidadRecibida = 0,
    this.precioCompra = 0,
  });

  /// Lo que se le paga al proveedor por esta línea.
  int get totalCompra => (cantidadRecibida * precioCompra).round();

  factory LineaConsolidado.fromMap(Map<String, dynamic> m) => LineaConsolidado(
        productoId: m['producto_id'] as String?,
        codigo: textOrNull(m['codigo']),
        descripcion: m['descripcion'] as String,
        unidad: (m['unidad'] as String?) ?? 'unidad',
        factor: m['factor'] == null ? 1 : toDouble(m['factor']),
        cantidad: toDouble(m['cantidad']),
        detalle: [for (final d in toMapList(m['detalle'])) DetalleLocal.fromMap(d)],
        nota: textOrNull(m['nota']),
        recepcion: EstadoRecepcion.de(m['recepcion'] as String?),
        cantidadRecibida: toDouble(m['cantidad_recibida']),
        precioCompra: toInt(m['precio_compra']),
      );

  Map<String, dynamic> toMap() => {
        'producto_id': productoId,
        'codigo': codigo,
        'descripcion': descripcion,
        'unidad': unidad,
        'factor': factor,
        'cantidad': cantidad,
        'detalle': [for (final d in detalle) d.toMap()],
        'nota': nota,
        'recepcion': recepcion.valor,
        'cantidad_recibida': cantidadRecibida,
        'precio_compra': precioCompra,
      };
}

/// La hoja para el proveedor: todos los pedidos sumados por producto.
class Consolidado {
  final String id;
  final int numero;
  final DateTime fecha;
  final String proveedorId;
  final String proveedorNombre;
  final String? proveedorTelefono;
  final List<String> pedidoIds;
  final List<LineaConsolidado> lineas;

  /// 'enviado' (esperando la mercadería), 'recibido' o 'anulado'.
  final String estado;
  final DateTime? fechaRecepcion;
  final String? recibidoPor;
  final String? creadoPor;

  /// Lista de compras: la compra la hace el administrador mismo (no se le
  /// mandó a un proveedor).
  final bool directa;

  /// Por qué se anuló, quién y cuándo.
  final String? motivo;
  final String? anuladoPor;
  final DateTime? fechaAnulacion;

  const Consolidado({
    required this.id,
    required this.numero,
    required this.fecha,
    required this.proveedorId,
    required this.proveedorNombre,
    this.proveedorTelefono,
    required this.pedidoIds,
    required this.lineas,
    this.estado = 'enviado',
    this.fechaRecepcion,
    this.recibidoPor,
    this.creadoPor,
    this.directa = false,
    this.motivo,
    this.anuladoPor,
    this.fechaAnulacion,
  });

  bool get recibido => estado == 'recibido';
  bool get anulado => estado == 'anulado';
  bool get esperando => estado == 'enviado';
  int get totalCompra => lineas.fold(0, (s, l) => s + l.totalCompra);
  int get cantidadLocales => {for (final l in lineas) for (final d in l.detalle) d.pedidoId}.length;

  factory Consolidado.fromMap(Map<String, dynamic> m) => Consolidado(
        id: m['id'] as String,
        numero: toInt(m['numero']),
        fecha: toDate(m['fecha']),
        proveedorId: m['proveedor_id'] as String,
        proveedorNombre: m['proveedor_nombre'] as String,
        proveedorTelefono: textOrNull(m['proveedor_telefono']),
        pedidoIds: [for (final p in (m['pedido_ids'] as List? ?? const [])) p as String],
        lineas: [for (final l in toMapList(m['lineas'])) LineaConsolidado.fromMap(l)],
        estado: (m['estado'] as String?) ?? 'enviado',
        fechaRecepcion: toDateOrNull(m['fecha_recepcion']),
        recibidoPor: m['recibido_por'] as String?,
        creadoPor: m['creado_por'] as String?,
        directa: m['directa'] == true,
        motivo: textOrNull(m['motivo']),
        anuladoPor: textOrNull(m['anulado_por']),
        fechaAnulacion: toDateOrNull(m['fecha_anulacion']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'numero': numero,
        'fecha': fecha.toIso8601String(),
        'proveedor_id': proveedorId,
        'proveedor_nombre': proveedorNombre,
        'proveedor_telefono': proveedorTelefono,
        'pedido_ids': pedidoIds,
        'lineas': [for (final l in lineas) l.toMap()],
        'estado': estado,
        'fecha_recepcion': fechaRecepcion?.toIso8601String(),
        'recibido_por': recibidoPor,
        'creado_por': creadoPor,
      };
}

/// Lo que se marca en la pantalla de recepción para un producto.
class MarcaRecepcion {
  final EstadoRecepcion estado;
  final double cantidadRecibida;
  final int precioCompra;

  /// lineaId -> cantidad que le toca a cada local (solo si llegó una parte).
  final Map<String, double> reparto;

  const MarcaRecepcion({required this.estado, required this.cantidadRecibida, required this.precioCompra, this.reparto = const {}});
}

/// Reparto sugerido cuando llega una parte: proporcional a lo que pidió cada
/// local, en números enteros si lo pedido es entero; lo que sobra va al que más pidió.
Map<String, double> repartoSugerido(List<DetalleLocal> detalle, double recibido) {
  final total = detalle.fold<double>(0, (s, d) => s + d.cantidad);
  if (total <= 0 || recibido <= 0) return {for (final d in detalle) d.lineaId: 0};
  if (recibido >= total) return {for (final d in detalle) d.lineaId: d.cantidad};
  final enteros = detalle.every((d) => d.cantidad == d.cantidad.roundToDouble()) && recibido == recibido.roundToDouble();
  final r = <String, double>{};
  var asignado = 0.0;
  for (final d in detalle) {
    final exacto = d.cantidad * recibido / total;
    final v = enteros ? exacto.floorToDouble() : double.parse(exacto.toStringAsFixed(3));
    r[d.lineaId] = v;
    asignado += v;
  }
  // Lo que queda por redondeo, de a uno a los que más pidieron (sin pasarse de lo pedido).
  var resto = double.parse((recibido - asignado).toStringAsFixed(3));
  final orden = [...detalle]..sort((a, b) => b.cantidad.compareTo(a.cantidad));
  final paso = enteros ? 1.0 : resto;
  while (resto > 0.0001) {
    var dio = false;
    for (final d in orden) {
      if (resto <= 0.0001) break;
      final libre = d.cantidad - r[d.lineaId]!;
      if (libre <= 0.0001) continue;
      final dar = [paso, resto, libre].reduce((a, b) => a < b ? a : b);
      r[d.lineaId] = double.parse((r[d.lineaId]! + dar).toStringAsFixed(3));
      resto = double.parse((resto - dar).toStringAsFixed(3));
      dio = true;
    }
    if (!dio) break;
  }
  return r;
}
