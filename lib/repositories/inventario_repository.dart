import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/compra.dart';
import '../models/movimiento.dart';
import '../security/registro_seguro.dart';
import '../utils/validacion.dart';

/// Stock: compras propias, ajustes, pérdidas, devoluciones al proveedor y movimientos.
class InventarioRepository {
  InventarioRepository(this._s, this._sesion);
  final Servidor _s;
  final Sesion _sesion;

  // SELECT movimientos (solo el administrador)
  Future<List<Movimiento>> movimientos({String? productoId, DateTime? desde, DateTime? hasta, TipoMovimiento? tipo}) async {
    _sesion.exigirAdmin();
    final filas = await _s.filas('movimientos', filtro: (q) {
      var r = q;
      if (productoId != null) r = r.eq('producto_id', productoId);
      if (tipo != null) r = r.eq('tipo', tipo.valor);
      if (desde != null) r = r.gte('fecha', desde.toUtc().toIso8601String());
      if (hasta != null) r = r.lte('fecha', hasta.toUtc().toIso8601String());
      return r;
    }, orden: 'fecha', ascendente: false);
    return [for (final f in filas) Movimiento.fromMap(f)];
  }

  /// Ajuste por conteo: deja el stock en [nuevoStock] (rpc ajustar_stock).
  Future<void> ajustar(String productoId, double nuevoStock, String motivo, {required String clave}) async {
    _sesion.exigirAdmin();
    final m = _motivo(motivo);
    if (nuevoStock < 0 || nuevoStock > cantidadMaxima) throw const ErrorNegocio('Revisá la cantidad.');
    await _s.rpc('ajustar_stock', {'p_clave': clave, 'p_producto': productoId, 'p_nuevo': nuevoStock, 'p_motivo': m});
  }

  /// Mercadería perdida, vencida o rota.
  Future<void> perdida(String productoId, double cant, String motivo, {required String clave}) =>
      _salida(productoId, cant, motivo, TipoMovimiento.perdida, clave);

  /// Devolución al proveedor.
  Future<void> devolver(String productoId, double cant, String motivo, {required String clave}) =>
      _salida(productoId, cant, motivo, TipoMovimiento.devolucionProveedor, clave);

  // rpc salida_stock
  Future<void> _salida(String productoId, double cant, String motivo, TipoMovimiento tipo, String clave) async {
    _sesion.exigirAdmin();
    final m = _motivo(motivo);
    if (cant <= 0 || cant > cantidadMaxima) throw const ErrorNegocio('Revisá la cantidad.');
    await _s.rpc('salida_stock', {'p_clave': clave, 'p_producto': productoId, 'p_cantidad': cant, 'p_motivo': m, 'p_tipo': tipo.valor});
  }

  /// Compra propia para tener mercadería (no es de un pedido) (rpc registrar_compra).
  Future<Compra> comprar({
    String? proveedorId,
    String? proveedorNombre,
    String? factura,
    required List<LineaCompra> lineas,
    required String clave,
  }) async {
    _sesion.exigirAdmin();
    if (lineas.isEmpty) throw const ErrorNegocio('Agregá al menos un producto.');
    for (final l in lineas) {
      if (l.cantidad <= 0 || l.cantidad > cantidadMaxima) throw ErrorNegocio('Revisá la cantidad de ${l.descripcion}.');
      if (l.costo <= 0 || l.costo > montoMaximo) throw ErrorNegocio('Poné el precio de compra de ${l.descripcion}.');
    }
    final fac = factura == null ? '' : limpiarTexto(factura);
    return Compra.fromMap(await _s.rpcMapa('registrar_compra', {
      'p_clave': clave,
      'p_proveedor_id': proveedorId,
      'p_proveedor_nombre': proveedorNombre,
      'p_factura': fac.isEmpty ? null : fac,
      'p_lineas': [for (final l in lineas) l.toMap()],
    }));
  }

  // SELECT compras (solo el administrador)
  Future<List<Compra>> compras({DateTime? desde, DateTime? hasta}) async {
    _sesion.exigirAdmin();
    final filas = await _s.filas('compras', filtro: (q) {
      var r = q;
      if (desde != null) r = r.gte('fecha', desde.toUtc().toIso8601String());
      if (hasta != null) r = r.lte('fecha', hasta.toUtc().toIso8601String());
      return r;
    }, orden: 'numero', ascendente: false);
    return [for (final f in filas) Compra.fromMap(f)];
  }

  String _motivo(String motivo) {
    final m = limpiarTexto(motivo);
    if (m.length < 3) throw const ErrorNegocio('Escribí el motivo.');
    if (m.length > Largo.motivo) throw const ErrorNegocio('El motivo es muy largo.');
    return m;
  }
}
