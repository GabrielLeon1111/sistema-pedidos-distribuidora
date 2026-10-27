import '../data/clave_operacion.dart';
import '../data/local.dart';
import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/producto.dart';
import '../security/registro_seguro.dart';
import '../utils/validacion.dart';

class ProductoRepository {
  ProductoRepository(this._s, this._sesion, this._local);
  final Servidor _s;
  final Sesion _sesion;
  final Local _local;

  /// rpc listar_productos: al vendedor le llegan sin precio de compra ni costo.
  /// Sin señal: la copia del teléfono (para levantar pedidos con su último precio).
  Future<List<Producto>> listar({bool incluirInactivos = false}) async {
    _sesion.exigirUsuario();
    List<Map<String, dynamic>> filas;
    try {
      filas = await _s.rpcLista('listar_productos', {'p_incluir_inactivos': true});
      await _local.guardarCopia('productos', filas);
    } catch (e) {
      if (!esSinConexion(e)) rethrow;
      filas = await _local.copia('productos');
    }
    return [
      for (final f in filas)
        if (incluirInactivos || f['activo'] != false) Producto.fromMap(f),
    ];
  }

  Future<Producto?> obtener(String id) async {
    for (final p in await listar(incluirInactivos: true)) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<List<String>> categorias() async => {
        for (final p in await listar(incluirInactivos: true))
          if (p.categoria != null) p.categoria!,
      }.toList()
        ..sort();

  /// Crea o edita un producto (rpc guardar_producto). El vendedor solo puede
  /// crear (desde un pedido); los precios de compra los cambia el administrador.
  Future<Producto> guardar(Producto p) async {
    _sesion.exigirUsuario();
    final nombre = limpiarTexto(p.nombre);
    if (nombre.length < 2) throw const ErrorNegocio('Escribí el nombre del producto.');
    if (p.precioVenta < 0 || p.precioVenta > montoMaximo || p.precioCompra < 0 || p.precioCompra > montoMaximo) {
      throw const ErrorNegocio('Revisá los precios.');
    }
    final codigo = p.codigo == null ? null : limpiarTexto(p.codigo!);
    return Producto.fromMap(await _s.rpcMapa('guardar_producto', {
      'p': {
        ...p.toMap(),
        'nombre': nombre,
        'codigo': (codigo == null || codigo.isEmpty) ? null : codigo,
      },
    }));
  }

  // rpc activar_producto (solo el administrador)
  Future<void> activar(String id, bool activo) async {
    _sesion.exigirAdmin();
    await _s.rpc('activar_producto', {'p_id': id, 'p_activo': activo});
  }

  String nuevoId() => nuevaClave();
}
