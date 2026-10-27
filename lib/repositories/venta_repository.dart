import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/linea.dart';
import '../models/pago.dart';
import '../models/venta.dart';
import '../security/registro_seguro.dart';
import '../utils/validacion.dart';

/// Pago que se registra al entregar (o en una venta directa).
class PagoAlEntregar {
  final int monto;
  final String metodo;
  const PagoAlEntregar({required this.monto, this.metodo = 'efectivo'});
  static const fiado = PagoAlEntregar(monto: 0);
}

/// Entregas a los locales, notas de venta y ventas directas desde el stock.
/// Cada venta emite su factura con el timbrado vigente (en la base).
class VentaRepository {
  VentaRepository(this._s, this._sesion);
  final Servidor _s;
  final Sesion _sesion;

  // SELECT ventas (solo el administrador)
  Future<List<Venta>> listar({String? clienteId, DateTime? desde, DateTime? hasta, bool soloConSaldo = false}) async {
    _sesion.exigirAdmin();
    final filas = await _s.filas('ventas', filtro: (q) {
      var r = q;
      if (clienteId != null) r = r.eq('cliente_id', clienteId);
      if (desde != null) r = r.gte('fecha', desde.toUtc().toIso8601String());
      if (hasta != null) r = r.lte('fecha', hasta.toUtc().toIso8601String());
      return r;
    }, orden: 'numero', ascendente: false);
    final r = [for (final f in filas) Venta.fromMap(f)];
    return soloConSaldo ? r.where((v) => v.saldo > 0).toList() : r;
  }

  Future<Venta> obtener(String id) async {
    _sesion.exigirAdmin();
    final f = await _s.fila('ventas', id);
    if (f == null) throw const ErrorNegocio('La nota de venta ya no existe.');
    return Venta.fromMap(f);
  }

  /// Cuánto hay de seña para este pedido (para no cobrar de más al entregar).
  Future<int> senaDePedido(String pedidoId) async {
    final filas = await _s.filas('pagos', filtro: (q) => q.eq('pedido_id', pedidoId).eq('anulado', false));
    return [for (final f in filas) Pago.fromMap(f)].fold<int>(0, (s, p) => s + p.aFavor);
  }

  /// Entrega el pedido y genera la nota de venta con lo que el local realmente
  /// recibió (rpc entregar_pedido). [recibido]: lineaId -> cantidad que recibió
  /// (null = recibió todo). Lo que no recibió entra al stock con lo que se pagó.
  Future<Venta> entregar(
    String pedidoId, {
    Map<String, double>? recibido,
    PagoAlEntregar pago = PagoAlEntregar.fiado,
    String? observaciones,
    String? notaRemision,
    required String clave,
  }) async {
    _sesion.exigirAdmin();
    _validarPago(pago);
    return Venta.fromMap(await _s.rpcMapa('entregar_pedido', {
      'p_clave': clave,
      'p_pedido': pedidoId,
      'p_recibido': recibido,
      'p_pago_monto': pago.monto,
      'p_pago_metodo': pago.metodo,
      'p_observaciones': observaciones,
      'p_nota_remision': _remision(notaRemision),
    }));
  }

  /// El local no estaba: el pedido queda pendiente con nueva fecha (rpc no_estaba).
  Future<void> noEstaba(String pedidoId, DateTime nuevaFecha, {required String clave}) async {
    _sesion.exigirAdmin();
    await _s.rpc('no_estaba', {'p_clave': clave, 'p_pedido': pedidoId, 'p_fecha': nuevaFecha.toUtc().toIso8601String()});
  }

  /// El local no recibió nada: queda rechazado con el motivo y la mercadería
  /// entra al stock (rpc rechazar_pedido).
  Future<void> rechazar(String pedidoId, String motivo, {required String clave}) async {
    _sesion.exigirAdmin();
    final m = limpiarTexto(motivo);
    if (m.length < 3) throw const ErrorNegocio('Escribí el motivo.');
    await _s.rpc('rechazar_pedido', {'p_clave': clave, 'p_pedido': pedidoId, 'p_motivo': m});
  }

  /// Venta directa desde el stock, sin pedido previo (rpc venta_directa).
  Future<Venta> ventaDirecta({
    required String clienteId,
    required List<Linea> lineas,
    PagoAlEntregar pago = PagoAlEntregar.fiado,
    String? observaciones,
    String? notaRemision,
    required String clave,
  }) async {
    _sesion.exigirAdmin();
    if (lineas.isEmpty) throw const ErrorNegocio('Agregá al menos un producto.');
    for (final l in lineas) {
      if (l.productoId == null) throw ErrorNegocio('${l.descripcion} no está en el inventario.');
      if (l.cantidad <= 0) throw ErrorNegocio('Revisá la cantidad de ${l.descripcion}.');
    }
    _validarPago(pago);
    return Venta.fromMap(await _s.rpcMapa('venta_directa', {
      'p_clave': clave,
      'p_cliente': clienteId,
      'p_lineas': [for (final l in lineas) l.toMap()],
      'p_pago_monto': pago.monto,
      'p_pago_metodo': pago.metodo,
      'p_observaciones': observaciones,
      'p_nota_remision': _remision(notaRemision),
    }));
  }

  /// Anula una nota de venta (rpc anular_venta): la mercadería vuelve al stock
  /// y lo pagado queda a favor del local.
  Future<void> anular(String ventaId, String motivo, {required String clave}) async {
    _sesion.exigirAdmin();
    final m = limpiarTexto(motivo);
    if (m.length < 3) throw const ErrorNegocio('Escribí el motivo.');
    await _s.rpc('anular_venta', {'p_clave': clave, 'p_id': ventaId, 'p_motivo': m});
  }

  void _validarPago(PagoAlEntregar pago) {
    if (pago.monto < 0) throw const ErrorNegocio('El monto no puede ser negativo.');
    if (pago.monto > 0 && !metodosPago.contains(pago.metodo)) throw const ErrorNegocio('Elegí cómo pagó.');
  }

  String? _remision(String? r) {
    final t = r == null ? '' : limpiarTexto(r);
    return t.isEmpty ? null : t;
  }
}
