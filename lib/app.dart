import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'data/local.dart';
import 'data/servidor.dart';
import 'data/sesion.dart';
import 'providers/auth_provider.dart';
import 'providers/negocio_provider.dart';
import 'providers/refresh_bus.dart';
import 'providers/sincronizacion_provider.dart';
import 'repositories/cliente_repository.dart';
import 'repositories/cobro_repository.dart';
import 'repositories/gasto_repository.dart';
import 'repositories/historial_repository.dart';
import 'repositories/inventario_repository.dart';
import 'repositories/negocio_repository.dart';
import 'repositories/pedido_repository.dart';
import 'repositories/producto_repository.dart';
import 'repositories/proveedor_repository.dart';
import 'repositories/reporte_repository.dart';
import 'repositories/timbrado_repository.dart';
import 'repositories/usuario_repository.dart';
import 'repositories/venta_repository.dart';
import 'screens/auth/bloqueo_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/shell/home_shell.dart';
import 'theme/app_theme.dart';

class PedidosApp extends StatelessWidget {
  const PedidosApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Una sola conexión (Supabase) y una sola sesión para todos los repositorios.
    final s = Servidor();
    final sesion = Sesion();
    // Lo que se guarda en el teléfono para levantar pedidos sin señal.
    final local = Local(sesion);
    final usuarios = UsuarioRepository(s, sesion);
    final negocio = NegocioRepository(s, sesion);
    final clientes = ClienteRepository(s, sesion, local);
    final productos = ProductoRepository(s, sesion, local);
    final pedidos = PedidoRepository(s, sesion, local);
    final bus = RefreshBus();
    return MultiProvider(
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
        ChangeNotifierProvider(create: (_) => AuthProvider(usuarios, sesion, local)..iniciar()),
        // Se lee del servidor al entrar (HomeShell); antes se muestra la copia del equipo.
        ChangeNotifierProvider(create: (_) => NegocioProvider(negocio)..restaurar()),
        ChangeNotifierProvider.value(value: bus),
        ChangeNotifierProvider(
          create: (_) => SincronizacionProvider(pedidos: pedidos, clientes: clientes, productos: productos, local: local, bus: bus),
        ),
      ],
      child: MaterialApp(
        title: 'Pedidos y Cobros',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es'), Locale('es', 'PY')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Respeta la letra grande del celular, pero con un tope para que nada se desarme.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3)),
            child: child!,
          );
        },
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Con la huella activada, si la app estuvo en el fondo más de un minuto, al volver se pide.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthProvider>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      auth.marcarEnFondo();
    } else if (state == AppLifecycleState.resumed) {
      auth.bloquearSiCorresponde();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return switch (auth.estado) {
      EstadoSesion.cargando => const Scaffold(body: Center(child: CircularProgressIndicator())),
      EstadoSesion.lista when auth.bloqueado => const BloqueoScreen(),
      // Cambia la clave del shell al cambiar de usuario: arranca de cero.
      EstadoSesion.lista => HomeShell(key: ValueKey(auth.usuario?.id)),
      EstadoSesion.sinSesion => const LoginScreen(),
    };
  }
}
