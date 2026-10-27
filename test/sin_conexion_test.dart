import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_pedidos/data/clave_operacion.dart';
import 'package:sistema_pedidos/data/local.dart';
import 'package:sistema_pedidos/data/servidor.dart';
import 'package:sistema_pedidos/data/sesion.dart';
import 'package:sistema_pedidos/models/cliente.dart';
import 'package:sistema_pedidos/models/linea.dart';
import 'package:sistema_pedidos/models/usuario.dart';
import 'package:sistema_pedidos/repositories/cliente_repository.dart';
import 'package:sistema_pedidos/repositories/pedido_repository.dart';
import 'package:sistema_pedidos/security/registro_seguro.dart';

/// Servidor de mentira: con [enLinea] en false, todo falla como si no hubiera señal.
class ServidorFalso extends Servidor {
  bool enLinea = true;
  final llamadas = <(String, Map<String, dynamic>)>[];
  final pedidos = <String, Map<String, dynamic>>{};
  final clientes = <String, Map<String, dynamic>>{};
  var _bloque = 21;

  void _senal() {
    if (!enLinea) throw const SocketException('sin señal');
  }

  @override
  Future<dynamic> rpc(String funcion, [Map<String, dynamic>? params]) async {
    _senal();
    final p = params ?? {};
    llamadas.add((funcion, p));
    switch (funcion) {
      case 'reservar_numeros_pedido':
        final desde = _bloque;
        _bloque += 20;
        return {'desde': desde, 'hasta': desde + 19};
      case 'listar_pedidos':
        return pedidos.values.toList();
      case 'guardar_cliente':
        final c = Map<String, dynamic>.from(p['p'] as Map);
        clientes[c['id'] as String] = c;
        return c;
      case 'guardar_pedido':
        final id = p['p_id'] as String;
        // Igual que la base: la misma clave devuelve lo mismo y no duplica.
        pedidos[id] = {
          'id': id,
          'numero': p['p_numero'],
          'fecha': p['p_fecha'],
          'cliente_id': p['p_cliente_id'],
          'cliente': {'nombre': clientes[p['p_cliente_id']]?['nombre'] ?? 'Local'},
          'lineas': p['p_lineas'],
          'estado': 'cargado',
        };
        return pedidos[id];
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> fila(String tabla, String id, {String columna = 'id'}) async {
    _senal();
    return tabla == 'clientes' ? clientes[id] : null;
  }

  @override
  Future<List<Map<String, dynamic>>> filas(String tabla, {Filtro? filtro, String orden = 'id', bool ascendente = true}) async {
    _senal();
    return tabla == 'clientes' ? clientes.values.toList() : [];
  }
}

void main() {
  late ServidorFalso s;
  late Local local;
  late PedidoRepository pedidos;
  late ClienteRepository clientes;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    s = ServidorFalso();
    final sesion = Sesion()..usuario = Usuario(id: 'u1', nombre: 'Juan Vendedor', usuario: 'juan', rol: 'vendedor', creado: DateTime(2026));
    local = Local(sesion);
    pedidos = PedidoRepository(s, sesion, local);
    clientes = ClienteRepository(s, sesion, local);
  });

  Linea linea(String desc, double cant, int precio) => Linea(id: nuevaClave(), descripcion: desc, cantidad: cant, precio: precio);

  test('sin señal la nota se guarda con su número definitivo y se sube sola después', () async {
    // Con señal: reserva el bloque de números (como al abrir la app).
    await pedidos.asegurarNumeros();
    expect(await local.numerosDisponibles(), 20);

    // Sin señal: local nuevo y nota de pedido.
    s.enLinea = false;
    final local1 = await clientes.guardar(Cliente(id: nuevaClave(), nombre: 'Despensa Sin Señal', creado: DateTime.now()));
    expect((await clientes.listar()).map((c) => c.nombre), contains('Despensa Sin Señal'));
    final clave = nuevaClave();
    final p = await pedidos.guardar(clienteId: local1.id, lineas: [linea('Kitadol Forte', 10, 9500)], clave: clave);
    expect(p.sinSincronizar, isTrue);
    expect(p.numero, 21, reason: 'El primer número del bloque reservado');
    expect(p.cliente.nombre, 'Despensa Sin Señal');
    expect((await pedidos.listar()).single.id, p.id, reason: 'Aparece en la lista aunque no haya señal');
    expect((await pedidos.obtener(p.id)).total, 95000);
    expect(await local.cantidadEnCola(), 2);

    // Se puede editar mientras no se subió: mantiene el id y el número.
    final editada = await pedidos.guardar(id: p.id, clienteId: local1.id, lineas: [linea('Kitadol Forte', 12, 9500)], clave: nuevaClave());
    expect(editada.numero, 21);
    expect((await pedidos.pendientesDeSubir()).single.lineas.single.cantidad, 12);

    // Vuelve la señal: primero el local, después la nota, con su id, número y fecha.
    s.enLinea = true;
    expect(await clientes.subirPendientes(), 1);
    expect(await pedidos.subirPendientes(), 1);
    expect(await local.cantidadEnCola(), 0);
    final subida = s.llamadas.lastWhere((l) => l.$1 == 'guardar_pedido').$2;
    expect(subida['p_id'], p.id);
    expect(subida['p_numero'], 21);
    expect(subida['p_fecha'], isNotNull);
    expect(s.pedidos[p.id]!['lineas'], hasLength(1));
    expect((await pedidos.listar()).single.sinSincronizar, isFalse);
  });

  test('si se corta a mitad de la subida, se reintenta con la misma clave (no duplica)', () async {
    await pedidos.asegurarNumeros();
    await clientes.guardar(Cliente(id: 'c1', nombre: 'Local Uno', creado: DateTime.now()));
    s.enLinea = false;
    final p = await pedidos.guardar(clienteId: 'c1', lineas: [linea('Arroz', 2, 6000)], clave: nuevaClave());
    s.enLinea = true;
    await pedidos.subirPendientes();
    await pedidos.subirPendientes();
    final envios = s.llamadas.where((l) => l.$1 == 'guardar_pedido').toList();
    expect(envios, hasLength(1), reason: 'Una vez subida sale de la cola');
    expect(s.pedidos.keys, [p.id]);
  });

  test('sin señal y sin números reservados avisa qué hacer', () async {
    s.enLinea = false;
    await expectLater(
      pedidos.guardar(clienteId: 'c1', lineas: [linea('Sal', 1, 2000)], clave: nuevaClave()),
      throwsA(isA<ErrorNegocio>().having((e) => e.mensaje, 'mensaje', contains('abrí la app una vez con conexión'))),
    );
  });
}
