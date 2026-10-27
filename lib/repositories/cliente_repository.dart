import '../data/local.dart';
import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/cliente.dart';
import '../models/json.dart';
import '../security/registro_seguro.dart';
import '../utils/validacion.dart';

/// Un pedido que el local no recibió (todo o una parte).
class Rechazo {
  final DateTime fecha;
  final int pedidoNumero;
  final String detalle;
  final int monto;
  const Rechazo({required this.fecha, required this.pedidoNumero, required this.detalle, required this.monto});

  factory Rechazo.fromMap(Map<String, dynamic> m) => Rechazo(
        fecha: toDate(m['fecha']),
        pedidoNumero: toInt(m['pedido_numero']),
        detalle: (m['detalle'] as String?) ?? '',
        monto: toInt(m['monto']),
      );
}

class ClienteRepository {
  ClienteRepository(this._s, this._sesion, this._local);
  final Servidor _s;
  final Sesion _sesion;
  final Local _local;

  // SELECT clientes (lo ven todos los usuarios). Sin señal: la copia del
  // teléfono. Siempre se suman los locales cargados sin señal.
  Future<List<Cliente>> listar({bool incluirInactivos = false}) async {
    _sesion.exigirUsuario();
    List<Map<String, dynamic>> filas;
    try {
      filas = await _s.filas('clientes', orden: 'nombre');
      await _local.guardarCopia('clientes', filas);
    } catch (e) {
      if (!esSinConexion(e)) rethrow;
      filas = await _local.copia('clientes');
    }
    final pendientes = await _local.cola('clientes');
    final ids = {for (final f in pendientes) f['id']};
    return [
      for (final f in [...pendientes, ...filas.where((f) => !ids.contains(f['id']))])
        if (incluirInactivos || f['activo'] != false) Cliente.fromMap(f),
    ]..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  }

  Future<Cliente?> obtener(String id) async {
    final pendiente = (await _local.cola('clientes')).where((f) => f['id'] == id).firstOrNull;
    if (pendiente != null) return Cliente.fromMap(pendiente);
    try {
      final f = await _s.fila('clientes', id);
      return f == null ? null : Cliente.fromMap(f);
    } catch (e) {
      if (!esSinConexion(e)) rethrow;
      final f = (await _local.copia('clientes')).where((f) => f['id'] == id).firstOrNull;
      return f == null ? null : Cliente.fromMap(f);
    }
  }

  /// Crea o actualiza un local (rpc guardar_cliente). El id lo pone la app:
  /// si se reintenta, actualiza el mismo local en vez de crear otro. Sin
  /// señal queda guardado en el teléfono y se sube solo después.
  Future<Cliente> guardar(Cliente c) async {
    _sesion.exigirUsuario();
    final nombre = limpiarTexto(c.nombre);
    if (nombre.length < 2) throw const ErrorNegocio('Escribí el nombre del local.');
    final err = validarTelefono(c.telefono) ?? validarDocumento(c.ruc);
    if (err != null) throw ErrorNegocio(err);
    final fila = {...c.toMap(), 'nombre': nombre};
    try {
      final guardado = await _s.rpcMapa('guardar_cliente', {'p': fila});
      await _local.quitarDeCola('clientes', c.id);
      // Queda en la copia del teléfono: se le pueden levantar pedidos aunque después se vaya la señal.
      await _local.ponerEnCopia('clientes', guardado);
      return Cliente.fromMap(guardado);
    } catch (e) {
      if (!esSinConexion(e)) rethrow;
      final copia = await _local.copia('clientes');
      if (copia.any((f) => f['id'] != c.id && (f['nombre'] as String).toLowerCase() == nombre.toLowerCase())) {
        throw const ErrorNegocio('Ya existe un local con ese nombre. Buscalo en la lista.');
      }
      await _local.ponerEnCola('clientes', {...fila, 'sin_sincronizar': true});
      return Cliente.fromMap(fila);
    }
  }

  /// Sube los locales cargados sin señal. Si se corta la señal, para.
  Future<int> subirPendientes() async {
    var subidos = 0;
    for (final f in await _local.cola('clientes')) {
      try {
        final guardado = await _s.rpcMapa('guardar_cliente', {'p': {...f}..remove('sin_sincronizar')..remove('error_sincronizacion')});
        await _local.quitarDeCola('clientes', f['id'] as String);
        await _local.ponerEnCopia('clientes', guardado);
        subidos++;
      } catch (e) {
        if (esSinConexion(e)) rethrow;
        registrarError('subirCliente', e);
        await _local.ponerEnCola('clientes', {...f, 'error_sincronizacion': mensajeErrorSeguro(e)});
      }
    }
    return subidos;
  }

  // rpc activar_cliente (solo el administrador)
  Future<void> activar(String id, bool activo) async {
    _sesion.exigirAdmin();
    await _s.rpc('activar_cliente', {'p_id': id, 'p_activo': activo});
  }

  /// Historial de rechazos del local (rpc rechazos_cliente): pedidos que no
  /// recibió y productos parciales que no aceptó o no recibió al entregar.
  Future<List<Rechazo>> rechazos(String clienteId) async {
    try {
      return [for (final f in await _s.rpcLista('rechazos_cliente', {'p_cliente': clienteId})) Rechazo.fromMap(f)];
    } catch (e) {
      if (esSinConexion(e)) return const [];
      rethrow;
    }
  }
}
