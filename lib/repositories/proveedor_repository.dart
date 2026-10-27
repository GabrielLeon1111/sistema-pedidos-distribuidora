import '../data/clave_operacion.dart';
import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/consolidado.dart';
import '../models/pedido.dart';
import '../models/proveedor.dart';
import '../security/registro_seguro.dart';
import '../utils/validacion.dart';

/// Nombre del "proveedor" de las listas de compras (no aparece para elegir).
const nombreCompraDirecta = 'Compra directa';

class ProveedorRepository {
  ProveedorRepository(this._s, this._sesion);
  final Servidor _s;
  final Sesion _sesion;

  // ---------------- Proveedores ----------------

  // SELECT proveedores (lo ven todos los usuarios)
  Future<List<Proveedor>> listar({bool incluirInactivos = false}) async {
    final filas = await _s.filas('proveedores', filtro: incluirInactivos ? null : (q) => q.eq('activo', true), orden: 'nombre');
    return [
      for (final f in filas)
        // "Compra directa" lo usa el sistema para lo que compra el administrador mismo.
        if (f['nombre'] != nombreCompraDirecta) Proveedor.fromMap(f),
    ]..sort((a, b) => a.nombre.compareTo(b.nombre));
  }

  /// rpc guardar_proveedor. El id lo pone la app: un reintento actualiza el mismo.
  Future<Proveedor> guardar(Proveedor p) async {
    _sesion.exigirAdmin();
    final nombre = limpiarTexto(p.nombre);
    if (nombre.length < 2) throw const ErrorNegocio('Escribí el nombre del proveedor.');
    final err = validarTelefono(p.telefono);
    if (err != null) throw ErrorNegocio(err);
    return Proveedor.fromMap(await _s.rpcMapa('guardar_proveedor', {'p': {...p.toMap(), 'nombre': nombre}}));
  }

  String nuevoId() => nuevaClave();

  // ---------------- Consolidado ----------------

  /// Pedidos cargados que todavía no se pidieron al proveedor (los que tienen
  /// algo para pedir; lo que sale del stock no va en la hoja).
  Future<List<Pedido>> pedidosParaConsolidar() async {
    _sesion.exigirAdmin();
    final filas = await _s.rpcLista('listar_pedidos', {'p_estados': [EstadoPedido.cargado.valor]});
    return [for (final f in filas) Pedido.fromMap(f)].where((p) => p.lineasAProveedor.isNotEmpty).toList()
      ..sort((a, b) => a.numero.compareTo(b.numero));
  }

  /// Arma la hoja para el proveedor sumando los pedidos elegidos por producto
  /// (rpc crear_consolidados). Si los productos son de distintos proveedores,
  /// sale una hoja para cada uno. Los pedidos pasan a "Pedido al proveedor".
  Future<List<Consolidado>> crearConsolidados(List<String> pedidoIds, {required String clave}) async {
    _sesion.exigirAdmin();
    if (pedidoIds.isEmpty) throw const ErrorNegocio('Elegí al menos un pedido.');
    final r = await _s.rpcLista('crear_consolidados', {'p_clave': clave, 'p_pedido_ids': pedidoIds});
    return [for (final m in r) Consolidado.fromMap(m)];
  }

  // SELECT consolidados (solo el administrador)
  /// Lista de compras (rpc crear_compra_directa): el administrador va él mismo
  /// a comprar todo lo de las notas pendientes y va marcando lo que compró.
  Future<Consolidado> crearListaCompras(List<String> pedidoIds, {required String clave}) async {
    _sesion.exigirAdmin();
    if (pedidoIds.isEmpty) throw const ErrorNegocio('No hay notas de pedido para comprar.');
    return Consolidado.fromMap(await _s.rpcMapa('crear_compra_directa', {'p_clave': clave, 'p_pedido_ids': pedidoIds}));
  }

  Future<List<Consolidado>> consolidados({bool? recibidos}) async {
    _sesion.exigirAdmin();
    final filas = await _s.filas(
      'consolidados',
      filtro: recibidos == null ? null : (q) => q.eq('estado', recibidos ? 'recibido' : 'enviado'),
      orden: 'numero',
      ascendente: false,
    );
    return [for (final f in filas) Consolidado.fromMap(f)];
  }

  Future<Consolidado> obtener(String id) async {
    _sesion.exigirAdmin();
    final f = await _s.fila('consolidados', id);
    if (f == null) throw const ErrorNegocio('El consolidado ya no existe.');
    return Consolidado.fromMap(f);
  }

  // ---------------- Recepción ----------------

  /// Registra lo que llegó de cada producto (por posición en la hoja), con la
  /// Anula un pedido al proveedor que todavía no llegó (rpc anular_consolidado):
  /// sus notas vuelven a "cargado" para editarlas o pedirlas de nuevo.
  Future<void> anular(String consolidadoId, String motivo, {required String clave}) async {
    _sesion.exigirAdmin();
    final m = limpiarTexto(motivo);
    if (m.length < 3) throw const ErrorNegocio('Escribí el motivo.');
    await _s.rpc('anular_consolidado', {'p_clave': clave, 'p_id': consolidadoId, 'p_motivo': m});
  }

  /// rpc registrar_recepcion:
  /// - Llegó completo: cada local recibe lo que pidió.
  /// - No llegó: se anula en los pedidos de los locales.
  /// - Llegó una parte: se reparte entre los locales y queda esperando que
  ///   cada uno confirme si acepta la cantidad menor.
  /// El precio de compra queda guardado como el último del producto.
  Future<Consolidado> registrarRecepcion(String consolidadoId, Map<int, MarcaRecepcion> marcas, {required String clave}) async {
    _sesion.exigirAdmin();
    final c = await obtener(consolidadoId);
    if (c.recibido) throw const ErrorNegocio('Esta mercadería ya se recibió.');
    if (c.anulado) throw const ErrorNegocio('Este pedido al proveedor está anulado.');
    final lista = <Map<String, dynamic>>[];
    for (var i = 0; i < c.lineas.length; i++) {
      final l = c.lineas[i];
      final m = marcas[i];
      if (m == null || m.estado == EstadoRecepcion.pendiente) throw ErrorNegocio('Marcá qué pasó con ${l.descripcion}.');
      // Sin reparto elegido, se propone el proporcional a lo que pidió cada local.
      final reparto = m.estado == EstadoRecepcion.parcial
          ? (m.reparto.isEmpty ? repartoSugerido(l.detalle, m.cantidadRecibida) : m.reparto)
          : const <String, double>{};
      lista.add({
        'estado': m.estado.valor,
        'cantidad_recibida': m.cantidadRecibida,
        'precio_compra': m.precioCompra,
        'reparto': reparto,
      });
    }
    return Consolidado.fromMap(
      await _s.rpcMapa('registrar_recepcion', {'p_clave': clave, 'p_consolidado': consolidadoId, 'p_marcas': lista}),
    );
  }
}
