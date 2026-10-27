import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/cliente.dart';
import '../models/pago.dart';
import '../models/venta.dart';
import '../security/registro_seguro.dart';
import '../utils/formato.dart';
import '../utils/validacion.dart';

/// Cuenta de un local: lo que debe, lo que tiene a favor y desde cuándo debe.
class CuentaCliente {
  final Cliente cliente;
  final int deuda;
  final int aFavor;
  final int notasConSaldo;

  /// Fecha de la nota impaga más vieja.
  final DateTime? deudaDesde;
  final int totalComprado;
  final int totalPagado;

  const CuentaCliente({
    required this.cliente,
    required this.deuda,
    required this.aFavor,
    required this.notasConSaldo,
    this.deudaDesde,
    this.totalComprado = 0,
    this.totalPagado = 0,
  });

  int? get diasDeuda => deudaDesde == null ? null : diasDesde(deudaDesde!);
}

/// Cobros: pagos (de a partes), fiado, señas y quién debe.
/// La app no cobra ni procesa pagos: solo los registra.
class CobroRepository {
  CobroRepository(this._s, this._sesion);
  final Servidor _s;
  final Sesion _sesion;

  /// Cuenta de cada local. [soloDeudores]: los que deben algo.
  /// [clienteId]: solo la de ese local (lee menos datos).
  Future<List<CuentaCliente>> cuentas({bool soloDeudores = false, String? clienteId}) async {
    _sesion.exigirAdmin();
    final (clientesF, ventasF, pagosF) = await (
      _s.filas('clientes', filtro: clienteId == null ? null : (q) => q.eq('id', clienteId)),
      _s.filas('ventas', filtro: (q) => clienteId == null ? q.eq('anulada', false) : q.eq('anulada', false).eq('cliente_id', clienteId)),
      _s.filas('pagos', filtro: (q) => clienteId == null ? q.eq('anulado', false) : q.eq('anulado', false).eq('cliente_id', clienteId)),
    ).wait;
    final ventas = [for (final f in ventasF) Venta.fromMap(f)];
    final pagos = [for (final f in pagosF) Pago.fromMap(f)];
    final r = <CuentaCliente>[];
    for (final f in clientesF) {
      final c = Cliente.fromMap(f);
      final vs = ventas.where((v) => v.clienteId == c.id).toList();
      final ps = pagos.where((p) => p.clienteId == c.id);
      final conSaldo = vs.where((v) => v.saldo > 0).toList()..sort((a, b) => a.fecha.compareTo(b.fecha));
      final cuenta = CuentaCliente(
        cliente: c,
        deuda: conSaldo.fold(0, (s, v) => s + v.saldo),
        aFavor: ps.fold(0, (s, p) => s + p.aFavor),
        notasConSaldo: conSaldo.length,
        deudaDesde: conSaldo.isEmpty ? null : conSaldo.first.fecha,
        totalComprado: vs.fold(0, (s, v) => s + v.total),
        totalPagado: ps.fold(0, (s, p) => s + p.monto),
      );
      if (soloDeudores && cuenta.deuda <= 0) continue;
      if (!soloDeudores && clienteId == null && !c.activo && vs.isEmpty) continue;
      r.add(cuenta);
    }
    r.sort((a, b) => b.deuda.compareTo(a.deuda));
    return r;
  }

  Future<CuentaCliente> cuenta(String clienteId) async {
    final r = await cuentas(clienteId: clienteId);
    if (r.isEmpty) throw const ErrorNegocio('El local ya no existe.');
    return r.single;
  }

  // SELECT pagos (solo el administrador)
  Future<List<Pago>> pagos({String? clienteId, DateTime? desde, DateTime? hasta}) async {
    _sesion.exigirAdmin();
    final filas = await _s.filas('pagos', filtro: (q) {
      var r = q;
      if (clienteId != null) r = r.eq('cliente_id', clienteId);
      if (desde != null) r = r.gte('fecha', desde.toUtc().toIso8601String());
      if (hasta != null) r = r.lte('fecha', hasta.toUtc().toIso8601String());
      return r;
    }, orden: 'numero', ascendente: false);
    return [for (final f in filas) Pago.fromMap(f)];
  }

  Future<Pago> obtener(String id) async {
    _sesion.exigirAdmin();
    final f = await _s.fila('pagos', id);
    if (f == null) throw const ErrorNegocio('El pago ya no existe.');
    return Pago.fromMap(f);
  }

  /// Registra un pago del local (rpc registrar_pago). Se aplica primero a
  /// [ventaId] (si se eligió una nota) y lo que sobra a las notas más viejas.
  /// Con [pedidoId] es una seña o adelanto que espera la entrega de ese pedido.
  Future<Pago> registrar({
    required String clienteId,
    required int monto,
    required String metodo,
    DateTime? fecha,
    String? nota,
    String? ventaId,
    String? pedidoId,
    required String clave,
  }) async {
    _sesion.exigirAdmin();
    if (monto <= 0 || monto > montoMaximo) throw const ErrorNegocio('Revisá el monto.');
    if (!metodosPago.contains(metodo)) throw const ErrorNegocio('Elegí cómo pagó.');
    if (fecha != null && fecha.isAfter(DateTime.now().add(const Duration(minutes: 5)))) throw const ErrorNegocio('La fecha no puede ser futura.');
    final texto = nota == null ? '' : limpiarTexto(nota);
    return Pago.fromMap(await _s.rpcMapa('registrar_pago', {
      'p_clave': clave,
      'p_cliente': clienteId,
      'p_monto': monto,
      'p_metodo': metodo,
      'p_fecha': fecha?.toUtc().toIso8601String(),
      'p_nota': texto.isEmpty ? null : texto,
      'p_venta': ventaId,
      'p_pedido': pedidoId,
    }));
  }

  /// Anula un pago con motivo (rpc anular_pago): deja de descontar de la deuda.
  Future<void> anular(String pagoId, String motivo, {required String clave}) async {
    _sesion.exigirAdmin();
    final m = limpiarTexto(motivo);
    if (m.length < 3) throw const ErrorNegocio('Escribí el motivo.');
    await _s.rpc('anular_pago', {'p_clave': clave, 'p_id': pagoId, 'p_motivo': m});
  }
}
