// Capturas de pantalla para el README, con datos de ejemplo (nada real).
// No usa la base: un servidor de mentira devuelve locales, productos, notas,
// ventas y una lista de compras inventados.
//
//   CAPTURAS_DIR=docs/capturas flutter test test/capturas/capturas_test.dart
//
// Sin CAPTURAS_DIR la prueba solo arma las pantallas (sirve para ver que no se rompen).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_pedidos/data/local.dart';
import 'package:sistema_pedidos/data/servidor.dart';
import 'package:sistema_pedidos/data/sesion.dart';
import 'package:sistema_pedidos/models/consolidado.dart';
import 'package:sistema_pedidos/models/usuario.dart';
import 'package:sistema_pedidos/providers/auth_provider.dart';
import 'package:sistema_pedidos/providers/negocio_provider.dart';
import 'package:sistema_pedidos/providers/refresh_bus.dart';
import 'package:sistema_pedidos/providers/sincronizacion_provider.dart';
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
import 'package:sistema_pedidos/screens/auth/login_screen.dart';
import 'package:sistema_pedidos/screens/inventario/inventario_screen.dart';
import 'package:sistema_pedidos/screens/pedidos/pedido_detalle_screen.dart';
import 'package:sistema_pedidos/screens/proveedor/consolidado_screen.dart';
import 'package:sistema_pedidos/screens/proveedor/recepcion_screen.dart';
import 'package:sistema_pedidos/screens/shell/home_shell.dart';
import 'package:sistema_pedidos/theme/app_theme.dart';

import 'datos_demo.dart';

class ServidorDemo extends Servidor {
  @override
  Future<List<Map<String, dynamic>>> filas(String tabla, {Filtro? filtro, String orden = 'id', bool ascendente = true}) async =>
      switch (tabla) {
        'clientes' => Demo.clientes,
        'ventas' => Demo.ventas,
        'pagos' => Demo.pagos,
        'productos' => Demo.productos,
        'consolidados' => Demo.consolidados,
        'proveedores' => Demo.proveedores,
        _ => <Map<String, dynamic>>[],
      };

  @override
  Future<Map<String, dynamic>?> fila(String tabla, String id, {String columna = 'id'}) async {
    if (tabla == 'negocio') return Demo.negocio;
    final lista = await filas(tabla);
    return lista.where((f) => f['id'] == id).firstOrNull;
  }

  @override
  Future<dynamic> rpc(String funcion, [Map<String, dynamic>? params]) async {
    switch (funcion) {
      case 'encabezado_negocio':
        return {...Demo.negocio, 'tiene_admin': true};
      case 'listar_productos':
        return Demo.productos;
      case 'listar_pedidos':
        final estados = params?['p_estados'] as List?;
        return [for (final p in Demo.pedidos) if (estados == null || estados.contains(p['estado'])) p];
      case 'obtener_pedido':
        return Demo.pedidos.firstWhere((p) => p['id'] == params?['p_id']);
      case 'senas_pedido':
      case 'rechazos_cliente':
        return <Map<String, dynamic>>[];
      case 'reservar_numeros_pedido':
        return {'desde': 900, 'hasta': 919};
    }
    return <Map<String, dynamic>>[];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = Platform.environment['CAPTURAS_DIR'];

  setUpAll(() async {
    await initializeDateFormatting('es');
    // Letras de la app (en las pruebas no se cargan solas).
    Future<void> fuente(String familia, List<String> archivos) async {
      final f = FontLoader(familia);
      for (final a in archivos) {
        f.addFont(Future.value(ByteData.view(File(a).readAsBytesSync().buffer)));
      }
      await f.load();
    }

    await fuente('Barlow', [for (final p in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/Barlow-$p.ttf']);
    await fuente('DMSerif', ['assets/fonts/DMSerifDisplay-Regular.ttf']);
    final flutter = Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter';
    await fuente('MaterialIcons', ['$flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf']);
  });

  final clave = GlobalKey();

  Future<void> armar(WidgetTester tester, Widget pantalla, {bool conSesion = true}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    final s = ServidorDemo();
    final sesion = Sesion();
    if (conSesion) sesion.usuario = Usuario(id: 'admin', nombre: 'Juan Benítez', usuario: 'admin', rol: 'admin', creado: DateTime(2026));
    final local = Local(sesion);
    final usuarios = UsuarioRepository(s, sesion);
    final negocio = NegocioRepository(s, sesion);
    final clientes = ClienteRepository(s, sesion, local);
    final productos = ProductoRepository(s, sesion, local);
    final pedidos = PedidoRepository(s, sesion, local);
    final bus = RefreshBus();
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: MultiProvider(
        providers: [
          Provider.value(value: sesion),
          Provider.value(value: local),
          Provider.value(value: usuarios),
          Provider.value(value: negocio),
          Provider.value(value: clientes),
          Provider.value(value: productos),
          Provider.value(value: pedidos),
          Provider(create: (_) => ProveedorRepository(s, sesion)),
          Provider(create: (_) => VentaRepository(s, sesion)),
          Provider(create: (_) => CobroRepository(s, sesion)),
          Provider(create: (_) => InventarioRepository(s, sesion)),
          Provider(create: (_) => GastoRepository(s, sesion)),
          Provider(create: (_) => ReporteRepository(s, sesion)),
          Provider(create: (_) => HistorialRepository(s, sesion)),
          Provider(create: (_) => TimbradoRepository(s, sesion)),
          ChangeNotifierProvider(create: (_) => AuthProvider(usuarios, sesion, local)),
          ChangeNotifierProvider(create: (_) => NegocioProvider(negocio)..restaurar()),
          ChangeNotifierProvider.value(value: bus),
          ChangeNotifierProvider(
            create: (_) => SincronizacionProvider(pedidos: pedidos, clientes: clientes, productos: productos, local: local, bus: bus),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          locale: const Locale('es'),
          supportedLocales: const [Locale('es')],
          localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: pantalla,
        ),
      ),
    ));
    await esperar(tester);
  }

  Future<void> guardar(WidgetTester tester, String nombre) async {
    await esperar(tester);
    if (carpeta == null) return;
    await tester.runAsync(() async {
      final boundary = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
      File('$carpeta/$nombre.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  testWidgets('1 ingreso', (tester) async {
    await armar(tester, const LoginScreen(), conSesion: false);
    await guardar(tester, '1_ingreso');
    await cerrar(tester);
  });

  for (final (nombre, tab) in [('2_inicio', HomeShell.inicio), ('3_pedidos', HomeShell.pedidos), ('5_proveedor', HomeShell.proveedor)]) {
    testWidgets(nombre, (tester) async {
      await armar(tester, const HomeShell());
      HomeShell.tab.value = tab;
      await guardar(tester, nombre);
      await cerrar(tester);
    });
  }

  testWidgets('4 nota de pedido', (tester) async {
    await armar(tester, PedidoDetalleScreen(id: Demo.pedidos.first['id'] as String));
    await guardar(tester, '4_nota_de_pedido');
    await cerrar(tester);
  });

  testWidgets('6 hoja del proveedor', (tester) async {
    await armar(tester, ConsolidadoScreen(id: Demo.consolidados.first['id'] as String));
    await guardar(tester, '6_hoja_proveedor');
    await cerrar(tester);
  });

  testWidgets('8 inventario', (tester) async {
    await armar(tester, const InventarioScreen());
    await guardar(tester, '8_inventario');
    await cerrar(tester);
  });

  testWidgets('7 lista de compras', (tester) async {
    final lista = Consolidado.fromMap(Demo.consolidados.last);
    await armar(tester, RecepcionScreen(consolidado: lista));
    // Algunos productos ya marcados, como a mitad de la compra.
    await tester.tap(find.text('Compré todo').first);
    await esperar(tester);
    await guardar(tester, '7_lista_de_compras');
    await cerrar(tester);
  });
}

Future<void> esperar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}
