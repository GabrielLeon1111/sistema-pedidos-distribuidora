import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/gasto.dart';
import '../security/registro_seguro.dart';
import '../utils/validacion.dart';

class GastoRepository {
  GastoRepository(this._s, this._sesion);
  final Servidor _s;
  final Sesion _sesion;

  // SELECT gastos (solo el administrador)
  Future<List<Gasto>> listar({DateTime? desde, DateTime? hasta, String? categoria}) async {
    _sesion.exigirAdmin();
    final filas = await _s.filas('gastos', filtro: (q) {
      var r = q;
      if (desde != null) r = r.gte('fecha', desde.toUtc().toIso8601String());
      if (hasta != null) r = r.lte('fecha', hasta.toUtc().toIso8601String());
      if (categoria != null) r = r.eq('categoria', categoria);
      return r;
    }, orden: 'fecha', ascendente: false);
    return [for (final f in filas) Gasto.fromMap(f)];
  }

  // rpc registrar_gasto
  Future<Gasto> registrar({
    required String categoria,
    required int monto,
    DateTime? fecha,
    String? descripcion,
    String? factura,
    required String clave,
  }) async {
    _sesion.exigirAdmin();
    if (!categoriasGasto.contains(categoria)) throw const ErrorNegocio('Elegí la categoría.');
    if (monto <= 0 || monto > montoMaximo) throw const ErrorNegocio('Revisá el monto.');
    if (fecha != null && fecha.isAfter(DateTime.now().add(const Duration(minutes: 5)))) throw const ErrorNegocio('La fecha no puede ser futura.');
    String? t(String? v) {
      final x = v == null ? '' : limpiarTexto(v);
      return x.isEmpty ? null : x;
    }

    return Gasto.fromMap(await _s.rpcMapa('registrar_gasto', {
      'p_clave': clave,
      'p_categoria': categoria,
      'p_monto': monto,
      'p_fecha': fecha?.toUtc().toIso8601String(),
      'p_descripcion': t(descripcion),
      'p_factura': t(factura),
    }));
  }

  // rpc anular_gasto
  Future<void> anular(String id, String motivo, {required String clave}) async {
    _sesion.exigirAdmin();
    final m = limpiarTexto(motivo);
    if (m.length < 3) throw const ErrorNegocio('Escribí el motivo.');
    await _s.rpc('anular_gasto', {'p_clave': clave, 'p_id': id, 'p_motivo': m});
  }
}
