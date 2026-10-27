import '../data/clave_operacion.dart';
import '../data/local.dart';
import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/cliente.dart';
import '../models/json.dart';
import '../models/linea.dart';
import '../models/pago.dart';
import '../models/pedido.dart';
import '../security/registro_seguro.dart';
import '../utils/validacion.dart';

/// Notas de pedido. Se pueden levantar sin señal: la nota se guarda en el
/// teléfono con un número de su bloque reservado (definitivo) y se sube sola
/// al volver la señal (ver SincronizacionProvider).
class PedidoRepository {
  PedidoRepository(this._s, this._sesion, this._local);
  final Servidor _s;
  final Sesion _sesion;
  final Local _local;

  /// Cuántos números de pedido se reservan por vez para trabajar sin señal.
  static const _bloque = 20;

  /// Con menos que esto, se reserva otro bloque (si hay señal).
  static const _minimoNumeros = 5;

  /// rpc listar_pedidos: al vendedor le llegan sin costos. Sin señal, la
  /// última copia del teléfono. Siempre se suman las notas sin subir.
  Future<List<Pedido>> listar({Set<EstadoPedido>? estados, String? clienteId, DateTime? desde, DateTime? hasta}) async {
    _sesion.exigirUsuario();
    bool pasa(Pedido p) =>
        (estados == null || estados.contains(p.estado)) &&
        (clienteId == null || p.clienteId == clienteId) &&
        (desde == null || !p.fecha.isBefore(desde)) &&
        (hasta == null || !p.fecha.isAfter(hasta));
    List<Pedido> servidor;
    try {
      final filas = await _s.rpcLista('listar_pedidos', {
        'p_estados': estados == null ? null : [for (final e in estados) e.valor],
        'p_cliente': clienteId,
        'p_desde': desde?.toUtc().toIso8601String(),
        'p_hasta': hasta?.toUtc().toIso8601String(),
      });
      if (estados == null && clienteId == null && desde == null && hasta == null) await _local.guardarCopia('pedidos', filas);
      servidor = [for (final f in filas) Pedido.fromMap(f)];
    } catch (e) {
      if (!esSinConexion(e)) rethrow;
      servidor = [for (final f in await _local.copia('pedidos')) Pedido.fromMap(f)].where(pasa).toList();
    }
    final ids = {for (final p in servidor) p.id};
    final pendientes = (await pendientesDeSubir()).where((p) => !ids.contains(p.id) && pasa(p));
    return [...pendientes, ...servidor]..sort((a, b) => b.numero.compareTo(a.numero));
  }

  // rpc obtener_pedido (sin señal: la nota sin subir o la copia del teléfono)
  Future<Pedido> obtener(String id) async {
    _sesion.exigirUsuario();
    final pendiente = (await pendientesDeSubir()).where((p) => p.id == id).firstOrNull;
    if (pendiente != null) return pendiente;
    try {
      return Pedido.fromMap(await _s.rpcMapa('obtener_pedido', {'p_id': id}));
    } catch (e) {
      if (!esSinConexion(e)) rethrow;
      final f = (await _local.copia('pedidos')).where((f) => f['id'] == id).firstOrNull;
      if (f == null) rethrow;
      return Pedido.fromMap(f);
    }
  }

  /// Señas o adelantos registrados para este pedido (rpc senas_pedido).
  Future<List<Pago>> senas(String pedidoId) async {
    try {
      return [for (final f in await _s.rpcLista('senas_pedido', {'p_id': pedidoId})) Pago.fromMap(f)];
    } catch (e) {
      if (esSinConexion(e)) return const [];
      rethrow;
    }
  }

  /// Guarda una nota de pedido nueva o editada (solo mientras no se pidió al
  /// proveedor). Los productos que no existen se agregan solos, y se recuerda
  /// el último precio de venta de cada uno.
  ///
  /// Una nota nueva (o una que todavía no se subió) se guarda primero en el
  /// teléfono con su número definitivo y se intenta subir: sin señal queda en
  /// la cola y se devuelve igual, marcada "sin sincronizar".
  Future<Pedido> guardar({
    required String clave,
    String? id,
    required String clienteId,
    required List<Linea> lineas,
    String? observaciones,
    DateTime? fechaEntrega,
  }) async {
    final u = _sesion.exigirUsuario();
    if (lineas.isEmpty) throw const ErrorNegocio('Agregá al menos un producto.');
    for (final l in lineas) {
      if (l.cantidad <= 0 || l.cantidad > cantidadMaxima) throw ErrorNegocio('Revisá la cantidad de ${l.descripcion}.');
      if (l.precio < 0 || l.precio > montoMaximo) throw ErrorNegocio('Revisá el precio de ${l.descripcion}.');
      if (l.descPct != null && (l.descPct! < 0 || l.descPct! > 100)) throw ErrorNegocio('El descuento de ${l.descripcion} tiene que ser de 0 a 100 %.');
      if (limpiarTexto(l.descripcion).length < 2) throw const ErrorNegocio('Hay un producto sin nombre.');
    }
    final obs = observaciones == null ? null : limpiarTexto(observaciones, multilinea: true);
    if (obs != null && obs.length > Largo.notas) throw const ErrorNegocio('Las observaciones son muy largas.');

    final anterior = id == null ? null : (await _local.cola('pedidos')).where((f) => f['id'] == id).firstOrNull;
    if (id != null && anterior == null) {
      // Editar una nota que ya está en el servidor: hace falta señal.
      try {
        return await _subir(clave: clave, id: id, clienteId: clienteId, lineas: lineas, obs: obs, fechaEntrega: fechaEntrega);
      } catch (e) {
        if (esSinConexion(e)) throw const ErrorNegocio('Sin señal no se puede editar una nota que ya se subió. Probá de nuevo cuando tengas conexión.');
        rethrow;
      }
    }

    final numero = anterior == null ? await _proximoNumero() : (anterior['numero'] as num).toInt();
    final item = <String, dynamic>{
      'id': id ?? nuevaClave(),
      'clave': clave,
      'numero': numero,
      'fecha': (anterior?['fecha'] as String?) ?? DateTime.now().toIso8601String(),
      'cliente_id': clienteId,
      'cliente': (await _datosCliente(clienteId)).toMap(),
      'vendedor_id': u.id,
      'vendedor_nombre': u.nombre,
      'lineas': [for (final l in lineas) l.toMap()],
      'observaciones': (obs == null || obs.isEmpty) ? null : obs,
      'fecha_entrega': fechaEntrega?.toIso8601String(),
      'estado': EstadoPedido.cargado.valor,
      'sin_sincronizar': true,
    };
    await _local.ponerEnCola('pedidos', item);
    try {
      return await _subirDeCola(item);
    } catch (e) {
      if (esSinConexion(e)) return Pedido.fromMap(item);
      // El servidor la rechazó: no queda en la cola, se avisa para corregir.
      await _local.quitarDeCola('pedidos', item['id'] as String);
      rethrow;
    }
  }

  /// Las notas levantadas en este teléfono que todavía no se subieron.
  Future<List<Pedido>> pendientesDeSubir() async => [for (final f in await _local.cola('pedidos')) Pedido.fromMap(f)];

  /// Sube las notas pendientes (en orden). Devuelve cuántas subió. Si se corta
  /// la señal, para y deja el resto para la próxima vez; si el servidor
  /// rechaza una, queda en la cola con el motivo para que se corrija.
  Future<int> subirPendientes() async {
    var subidas = 0;
    for (final item in await _local.cola('pedidos')) {
      try {
        await _subirDeCola(item);
        subidas++;
      } catch (e) {
        if (esSinConexion(e)) rethrow;
        registrarError('subirPedido', e);
        await _local.ponerEnCola('pedidos', {...item, 'error_sincronizacion': mensajeErrorSeguro(e)});
      }
    }
    return subidas;
  }

  /// Descarta una nota que todavía no se subió (solo está en este teléfono).
  Future<void> descartarPendiente(String id) => _local.quitarDeCola('pedidos', id);

  /// Reserva otro bloque de números si quedan pocos (necesita señal).
  Future<void> asegurarNumeros() async {
    if (await _local.numerosDisponibles() >= _minimoNumeros) return;
    final r = await _s.rpcMapa('reservar_numeros_pedido', {'p_cantidad': _bloque});
    await _local.agregarNumeros((r['desde'] as num).toInt(), (r['hasta'] as num).toInt());
  }

  Future<int> _proximoNumero() async {
    var n = await _local.tomarNumero();
    if (n == null) {
      try {
        await asegurarNumeros();
      } catch (e) {
        if (esSinConexion(e)) {
          throw const ErrorNegocio('Para levantar pedidos sin señal, abrí la app una vez con conexión (así reserva los números de pedido).');
        }
        rethrow;
      }
      n = await _local.tomarNumero();
    }
    if (n == null) throw const ErrorNegocio('No se pudieron reservar números de pedido. Intentá de nuevo.');
    return n;
  }

  /// Datos del local para la nota (también sin señal: de la copia o de los locales sin subir).
  Future<DatosCliente> _datosCliente(String clienteId) async {
    final filas = [...await _local.cola('clientes'), ...await _local.copia('clientes')];
    final f = filas.where((f) => f['id'] == clienteId).firstOrNull;
    if (f != null) return Cliente.fromMap(f).datos;
    try {
      final s = await _s.fila('clientes', clienteId);
      if (s == null) throw const ErrorNegocio('Elegí el local.');
      return Cliente.fromMap(s).datos;
    } catch (e) {
      if (esSinConexion(e)) throw const ErrorNegocio('Ese local no está guardado en el teléfono. Elegilo de nuevo cuando tengas señal.');
      rethrow;
    }
  }

  Future<Pedido> _subirDeCola(Map<String, dynamic> item) async {
    final p = await _subir(
      clave: item['clave'] as String,
      id: item['id'] as String,
      clienteId: item['cliente_id'] as String,
      lineas: [for (final l in toMapList(item['lineas'])) Linea.fromMap(l)],
      obs: item['observaciones'] as String?,
      fechaEntrega: item['fecha_entrega'] == null ? null : DateTime.parse(item['fecha_entrega'] as String),
      numero: (item['numero'] as num?)?.toInt(),
      fecha: DateTime.parse(item['fecha'] as String),
    );
    await _local.quitarDeCola('pedidos', item['id'] as String);
    return p;
  }

  // rpc guardar_pedido (con la clave contra duplicados: reintentar no duplica).
  Future<Pedido> _subir({
    required String clave,
    required String? id,
    required String clienteId,
    required List<Linea> lineas,
    String? obs,
    DateTime? fechaEntrega,
    int? numero,
    DateTime? fecha,
  }) async =>
      Pedido.fromMap(await _s.rpcMapa('guardar_pedido', {
        'p_clave': clave,
        'p_id': id,
        'p_cliente_id': clienteId,
        'p_lineas': [for (final l in lineas) l.toMap()],
        'p_observaciones': (obs == null || obs.isEmpty) ? null : obs,
        'p_fecha_entrega': fechaEntrega?.toUtc().toIso8601String(),
        'p_numero': numero,
        'p_fecha': fecha?.toUtc().toIso8601String(),
      }));

  /// Anula un pedido con motivo (rpc anular_pedido). Si la mercadería ya llegó, entra al stock.
  /// Llegó la mercadería de una nota que no pasó por la hoja del proveedor
  /// (rpc recibir_pedido): queda lista para entregar y facturar. [costos]:
  /// lo que se pagó por cada línea (por la forma en que se vende: docena, caja...).
  Future<Pedido> recibir(String id, Map<String, int> costos, {required String clave}) async {
    _sesion.exigirAdmin();
    if (costos.values.any((c) => c <= 0 || c > montoMaximo)) throw const ErrorNegocio('Poné el precio de compra de cada producto.');
    return Pedido.fromMap(await _s.rpcMapa('recibir_pedido', {'p_clave': clave, 'p_pedido': id, 'p_costos': costos}));
  }

  Future<void> anular(String id, String motivo, {required String clave}) async {
    _sesion.exigirUsuario();
    if (limpiarTexto(motivo).length < 3) throw const ErrorNegocio('Escribí el motivo.');
    await _s.rpc('anular_pedido', {'p_clave': clave, 'p_id': id, 'p_motivo': limpiarTexto(motivo)});
  }

  /// El local acepta (o no) la cantidad parcial que llegó de un producto
  /// (rpc confirmar_parcial). Si no acepta, ese producto se anula y lo que
  /// llegó entra al stock.
  Future<void> confirmarParcial(String pedidoId, String lineaId, {required bool acepta, required String clave}) async {
    _sesion.exigirUsuario();
    await _s.rpc('confirmar_parcial', {'p_clave': clave, 'p_pedido': pedidoId, 'p_linea': lineaId, 'p_acepta': acepta});
  }
}
