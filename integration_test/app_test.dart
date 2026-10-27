// =================================================================
//  PRUEBA COMPLETA EN UN CELULAR O EMULADOR (contra la base real)
//
//  Parte A: el circuito de datos con los repositorios (compra, locales,
//  pedidos, seña, consolidado, recepción con parcial, confirmación, entrega
//  con factura, cobro, venta directa, gastos, stock, reportes, historial,
//  anulaciones y anti-duplicados).
//  Parte B: las pantallas: entra con usuario y contraseña desde el login y
//  abre cada pestaña y cada módulo de "Más", sin errores.
//
//  Usa SOLO datos de prueba (locales y productos "ZZ ...") y un usuario de
//  prueba que se pasa al correrla (nunca queda en el código):
//    flutter test integration_test/app_test.dart -d <emulador> \
//      --dart-define-from-file=.env \
//      --dart-define=PRUEBA_USUARIO=prueba.claude --dart-define=PRUEBA_CLAVE=...
//  Las facturas de prueba deben salir de un timbrado de prueba activo.
// =================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sistema_pedidos/app.dart';
import 'package:sistema_pedidos/config/supabase_config.dart';
import 'package:sistema_pedidos/data/clave_operacion.dart';
import 'package:sistema_pedidos/data/local.dart';
import 'package:sistema_pedidos/data/servidor.dart';
import 'package:sistema_pedidos/data/sesion.dart';
import 'package:sistema_pedidos/models/cliente.dart';
import 'package:sistema_pedidos/models/compra.dart';
import 'package:sistema_pedidos/models/consolidado.dart';
import 'package:sistema_pedidos/models/linea.dart';
import 'package:sistema_pedidos/models/pedido.dart';
import 'package:sistema_pedidos/models/producto.dart';
import 'package:sistema_pedidos/repositories/cliente_repository.dart';
import 'package:sistema_pedidos/repositories/cobro_repository.dart';
import 'package:sistema_pedidos/repositories/gasto_repository.dart';
import 'package:sistema_pedidos/repositories/historial_repository.dart';
import 'package:sistema_pedidos/repositories/inventario_repository.dart';
import 'package:sistema_pedidos/repositories/negocio_repository.dart';
import 'package:sistema_pedidos/repositories/pedido_repository.dart';
import 'package:sistema_pedidos/repositories/producto_repository.dart';
import 'package:sistema_pedidos/repositories/proveedor_repository.dart';
import 'package:sistema_pedidos/repositories/reporte_repository.dart';
import 'package:sistema_pedidos/repositories/timbrado_repository.dart';
import 'package:sistema_pedidos/repositories/usuario_repository.dart';
import 'package:sistema_pedidos/repositories/venta_repository.dart';
import 'package:sistema_pedidos/services/imagen_pdf.dart';
import 'package:sistema_pedidos/services/pdf_documentos.dart';
import 'package:sistema_pedidos/services/pdf_factura.dart';
import 'package:sistema_pedidos/services/pdf_lista_compras.dart';

const _usuario = String.fromEnvironment('PRUEBA_USUARIO');
const _clave = String.fromEnvironment('PRUEBA_CLAVE');

/// Se agrega a los nombres de prueba: cada corrida crea sus propios datos.
final _corrida = '${DateTime.now().millisecondsSinceEpoch % 100000}';

/// Espera (bombeando cuadros) hasta que aparezca [f] o se termine el tiempo.
Future<void> esperar(WidgetTester tester, Finder f, {Duration tiempo = const Duration(seconds: 30)}) async {
  final fin = DateTime.now().add(tiempo);
  while (DateTime.now().isBefore(fin)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('No apareció: $f');
}

/// Vuelve a la pantalla anterior (espera a que aparezca el botón de volver).
Future<void> volver(WidgetTester tester) async {
  await esperar(tester, find.byType(BackButton));
  await tester.tap(find.byType(BackButton).first);
  await dejarCargar(tester, 800);
}

/// Bombea cuadros un rato (para que terminen las cargas de la red).
Future<void> dejarCargar(WidgetTester tester, [int ms = 2500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(_usuario, isNotEmpty, reason: 'Falta --dart-define=PRUEBA_USUARIO');
    expect(_clave, isNotEmpty, reason: 'Falta --dart-define=PRUEBA_CLAVE');
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
    await SupabaseConfig.init();
  });

  test('A · circuito completo de datos', () async {
    final s = Servidor();
    final sesion = Sesion();
    final usuarios = UsuarioRepository(s, sesion);
    await usuarios.ingresar(_usuario, _clave);
    sesion.usuario = await usuarios.miembroActual();
    expect(sesion.esAdmin, isTrue, reason: 'El usuario de prueba tiene que ser administrador');

    final local = Local(sesion);
    final productos = ProductoRepository(s, sesion, local);
    final clientes = ClienteRepository(s, sesion, local);
    final pedidos = PedidoRepository(s, sesion, local);
    final proveedor = ProveedorRepository(s, sesion);
    final ventas = VentaRepository(s, sesion);
    final cobros = CobroRepository(s, sesion);
    final inventario = InventarioRepository(s, sesion);
    final gastos = GastoRepository(s, sesion);
    final reportes = ReporteRepository(s, sesion);
    final historial = HistorialRepository(s, sesion);
    final negocio = await NegocioRepository(s, sesion).obtener();

    final timbrado = await TimbradoRepository(s, sesion).vigente();
    expect(timbrado?.numero, '99999999', reason: 'Tiene que estar activo el timbrado de prueba');

    // ---------- Productos de prueba y compra para tener stock ----------
    final hoy = DateTime.now();
    final med = await productos.guardar(Producto(id: nuevaClave(), nombre: 'ZZ Prueba Medicamento $_corrida', precioVenta: 10000, iva: 5, categoria: 'Medicamentos', creado: hoy));
    final lint = await productos.guardar(Producto(id: nuevaClave(), nombre: 'ZZ Prueba Linterna $_corrida', precioVenta: 20000, creado: hoy));
    final stk = await productos.guardar(Producto(id: nuevaClave(), nombre: 'ZZ Prueba Stock $_corrida', precioVenta: 5000, stockMinimo: 2, creado: hoy));
    await inventario.comprar(
      factura: '001-001-0000999',
      lineas: [LineaCompra(productoId: stk.id, descripcion: stk.nombre, unidad: 'unidad', cantidad: 10, costo: 3000)],
      clave: nuevaClave(),
    );
    final stkComprado = await productos.obtener(stk.id);
    expect(stkComprado!.stock, 10);
    expect(stkComprado.margenPorcentaje, closeTo(66.7, 0.1), reason: 'Margen = (5000 - 3000) / 3000');
    expect(stkComprado.gananciaUnidad, 2000);

    // ---------- Locales ----------
    final c1 = await clientes.guardar(Cliente(id: nuevaClave(), nombre: 'ZZ Prueba Local Uno $_corrida', ruc: '1234567-8', telefono: '0981 123456', creado: hoy));
    final c2 = await clientes.guardar(Cliente(id: nuevaClave(), nombre: 'ZZ Prueba Local Dos $_corrida', creado: hoy));

    // ---------- Pedidos (uno usa stock) ----------
    Linea l(Producto p, double cant, {bool deStock = false, double? descPct}) =>
        Linea(id: nuevaClave(), productoId: p.id, descripcion: p.nombre, cantidad: cant, precio: p.precioVenta, iva: p.iva, deStock: deStock, descPct: descPct);
    final claveP1 = nuevaClave();
    final p1 = await pedidos.guardar(clienteId: c1.id, lineas: [l(med, 5), l(lint, 2, descPct: 10)], clave: claveP1);
    final p1Repetido = await pedidos.guardar(clienteId: c1.id, lineas: [l(med, 5), l(lint, 2, descPct: 10)], clave: claveP1);
    expect(p1Repetido.id, p1.id, reason: 'Anti-duplicados: la misma clave no crea otro pedido');
    final p2 = await pedidos.guardar(clienteId: c2.id, lineas: [l(med, 3), l(stk, 2, deStock: true)], clave: nuevaClave());
    expect((await clientes.rechazos(c1.id)), isEmpty);

    // Seña del local 1.
    await cobros.registrar(clienteId: c1.id, monto: 10000, metodo: 'efectivo', pedidoId: p1.id, clave: nuevaClave());
    expect((await pedidos.senas(p1.id)).single.monto, 10000);

    // ---------- Consolidado y recepción (medicamento llega en parte) ----------
    expect((await proveedor.pedidosParaConsolidar()).map((p) => p.id), containsAll([p1.id, p2.id]));
    final hojas = await proveedor.crearConsolidados([p1.id, p2.id], clave: nuevaClave());
    expect(hojas, isNotEmpty);
    final hoja = hojas.single;
    expect((await pdfConsolidado(hoja, negocio)).length, greaterThan(1000));
    final marcas = <int, MarcaRecepcion>{};
    for (var i = 0; i < hoja.lineas.length; i++) {
      final linea = hoja.lineas[i];
      if (linea.productoId == med.id) {
        final d1 = linea.detalle.firstWhere((d) => d.pedidoId == p1.id);
        final d2 = linea.detalle.firstWhere((d) => d.pedidoId == p2.id);
        marcas[i] = MarcaRecepcion(estado: EstadoRecepcion.parcial, cantidadRecibida: 6, precioCompra: 7000, reparto: {d1.lineaId: 4, d2.lineaId: 2});
      } else {
        marcas[i] = MarcaRecepcion(estado: EstadoRecepcion.completo, cantidadRecibida: linea.cantidad, precioCompra: 12000);
      }
    }
    final recibido = await proveedor.registrarRecepcion(hoja.id, marcas, clave: nuevaClave());
    expect(recibido.recibido, isTrue);
    expect((await pdfRecepcion(recibido, negocio)).length, greaterThan(1000));

    // El local 1 acepta lo que llegó; el 2 no.
    var ped1 = await pedidos.obtener(p1.id);
    var ped2 = await pedidos.obtener(p2.id);
    await pedidos.confirmarParcial(p1.id, ped1.lineas.firstWhere((x) => x.productoId == med.id).id, acepta: true, clave: nuevaClave());
    await pedidos.confirmarParcial(p2.id, ped2.lineas.firstWhere((x) => x.productoId == med.id).id, acepta: false, clave: nuevaClave());
    ped1 = await pedidos.obtener(p1.id);
    ped2 = await pedidos.obtener(p2.id);
    expect(ped1.entregable, isTrue);
    expect((await clientes.rechazos(c2.id)), isNotEmpty, reason: 'Queda en el historial de rechazos del local');
    expect((await pdfNotaPedido(ped1, negocio, sena: 10000)).length, greaterThan(1000));

    // ---------- Entrega con factura (y repetida con la misma clave) ----------
    final claveEntrega = nuevaClave();
    final v1 = await ventas.entregar(p1.id, pago: const PagoAlEntregar(monto: 20000), notaRemision: '001-001-0000077', clave: claveEntrega);
    final v1Repetida = await ventas.entregar(p1.id, pago: const PagoAlEntregar(monto: 20000), notaRemision: '001-001-0000077', clave: claveEntrega);
    expect(v1Repetida.id, v1.id, reason: 'Anti-duplicados: no factura dos veces');
    expect(v1.factura?.timbrado, '99999999');
    // 4 × 10.000 + 2 × 20.000 − 10 % = 40.000 + 36.000
    expect(v1.total, 76000);
    expect(v1.pagado, 30000, reason: 'Seña 10.000 + 20.000 al entregar');
    final pdfFac = await pdfFactura(v1, negocio, duplicado: true);
    expect(pdfFac.length, greaterThan(1000));
    expect((await pdfNotaVenta(v1, negocio, duplicado: true)).length, greaterThan(1000));
    expect((await pdfAImagenes(await pdfFactura(v1, negocio))).length, 1, reason: 'La factura como imagen');

    // El local 2: no estaba, y después se le entrega fiado lo del stock.
    await ventas.noEstaba(p2.id, hoy.add(const Duration(days: 1)), clave: nuevaClave());
    expect((await pedidos.obtener(p2.id)).estado, EstadoPedido.pendiente);
    final v2 = await ventas.entregar(p2.id, clave: nuevaClave());
    expect(v2.total, 10000);
    expect(v2.saldo, 10000);

    // ---------- Cobros ----------
    final pago = await cobros.registrar(clienteId: c2.id, monto: 4000, metodo: 'transferencia', clave: nuevaClave());
    expect((await cobros.cuenta(c2.id)).deuda, 6000);
    expect((await pdfRecibo(pago, negocio, saldoRestante: 6000)).length, greaterThan(1000));
    await expectLater(cobros.registrar(clienteId: c2.id, monto: 999999, metodo: 'efectivo', clave: nuevaClave()), throwsA(anything),
        reason: 'No deja cobrar más de lo que debe');
    await cobros.anular(pago.id, 'Prueba de anulación', clave: nuevaClave());
    expect((await cobros.cuenta(c2.id)).deuda, 10000);

    // ---------- Venta directa desde el stock ----------
    final vd = await ventas.ventaDirecta(clienteId: c1.id, lineas: [l(stk, 3)], pago: const PagoAlEntregar(monto: 15000), clave: nuevaClave());
    expect(vd.saldo, 0);
    expect((await productos.obtener(stk.id))!.stock, 5, reason: '10 comprados − 2 entregados − 3 vendidos');

    // ---------- Stock: ajuste, averiados, devolución ----------
    await inventario.ajustar(stk.id, 6, 'Conteo de prueba', clave: nuevaClave());
    await inventario.perdida(stk.id, 1, 'Roto en prueba', clave: nuevaClave());
    await inventario.devolver(stk.id, 1, 'Devolución de prueba', clave: nuevaClave());
    expect((await productos.obtener(stk.id))!.stock, 4);
    expect((await inventario.movimientos(productoId: stk.id)).length, greaterThanOrEqualTo(5));
    final lista = [LineaCompraLista((await productos.obtener(stk.id))!, 4, '')];
    expect((await pdfListaCompras(lista, negocio)).length, greaterThan(1000));

    // ---------- Gastos ----------
    final g = await gastos.registrar(categoria: 'Combustible', monto: 50000, descripcion: 'ZZ prueba', clave: nuevaClave());
    await gastos.anular(g.id, 'Prueba de anulación', clave: nuevaClave());

    // ---------- Inicio, reportes, historial, usuarios ----------
    final panel = await reportes.panel();
    expect(panel.hoy.vendido, greaterThanOrEqualTo(76000 + 10000 + 15000));
    final rep = await reportes.reporte(hoy, hoy);
    expect(rep.vendido, greaterThanOrEqualTo(101000));
    expect(rep.productos, isNotEmpty);
    expect((await historial.cambios(desde: hoy.subtract(const Duration(hours: 1)))), isNotEmpty);
    expect((await historial.documentos(buscar: 'ZZ Prueba')), isNotEmpty);
    expect((await usuarios.listar()).any((u) => u.usuario == _usuario), isTrue);
    expect((await ventas.listar()).map((v) => v.id), containsAll([v1.id, v2.id, vd.id]));

    await usuarios.salir();
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('B · pantallas: login, pestañas y módulos de Más', (tester) async {
    await supa.auth.signOut();
    await tester.pumpWidget(const PedidosApp());
    await esperar(tester, find.text('Ingresar'));

    // Login con usuario y contraseña.
    await tester.enterText(find.widgetWithText(TextFormField, 'Email o usuario'), _usuario);
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), _clave);
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await esperar(tester, find.byType(NavigationBar));
    await dejarCargar(tester);
    // Si ofrece la huella, se cierra el aviso.
    if (find.text('Ahora no').evaluate().isNotEmpty) {
      await tester.tap(find.text('Ahora no'));
      await dejarCargar(tester, 800);
    }

    void sinErrores(String donde) {
      expect(tester.takeException(), isNull, reason: 'Error en $donde');
      expect(find.textContaining('No se pudo').evaluate(), isEmpty, reason: 'Mensaje de error en $donde');
    }

    // ---------- Pestañas de abajo ----------
    for (final pestana in ['Inicio', 'Pedidos', 'Ventas', 'Proveedor', 'Cobros', 'Más']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(pestana)));
      await dejarCargar(tester);
      sinErrores('la pestaña $pestana');
    }

    // ---------- Un pedido y una factura de prueba ----------
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Pedidos')));
    await dejarCargar(tester);
    await tester.tap(find.text('Todos'));
    await dejarCargar(tester, 800);
    await esperar(tester, find.text('ZZ Prueba Local Uno $_corrida'));
    await tester.tap(find.text('ZZ Prueba Local Uno $_corrida').first);
    await dejarCargar(tester);
    sinErrores('el detalle del pedido');
    await volver(tester);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Ventas')));
    await esperar(tester, find.text('ZZ Prueba Local Uno $_corrida'));
    await tester.tap(find.text('ZZ Prueba Local Uno $_corrida').first);
    // La sección de imprimir está más abajo: se desplaza hasta verla.
    await esperar(tester, find.text('Saldo'));
    await tester.scrollUntilVisible(find.text('Dos copias'), 300, scrollable: find.byType(Scrollable).first);
    await dejarCargar(tester, 800);
    // Los títulos de sección se muestran en mayúsculas.
    expect(find.textContaining(RegExp('imprimir o enviar', caseSensitive: false)), findsOneWidget);
    expect(find.text('Factura'), findsWidgets);
    expect(find.text('Nota de venta'), findsWidgets);
    expect(find.text('Dos copias'), findsOneWidget);
    sinErrores('el detalle de la factura');
    await volver(tester);

    // ---------- Módulos de "Más" ----------
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Más')));
    await dejarCargar(tester);
    for (final modulo in ['Inventario', 'Clientes', 'Gastos', 'Reportes', 'Historial', 'Timbrado', 'Datos del negocio', 'Proveedores', 'Usuarios']) {
      final item = find.text(modulo);
      await tester.scrollUntilVisible(item, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(item);
      await dejarCargar(tester, 3000);
      sinErrores('el módulo $modulo');
      if (modulo == 'Inventario') {
        expect(find.text('Lista de compras', findRichText: true).evaluate().isNotEmpty || find.textContaining('Lista de compras').evaluate().isNotEmpty, isTrue);
        await tester.tap(find.text('Movimientos'));
        await dejarCargar(tester);
        sinErrores('Inventario → Movimientos');
      }
      await volver(tester);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
