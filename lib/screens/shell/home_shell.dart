import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/negocio_provider.dart';
import '../../providers/sincronizacion_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/estado_sincronizacion.dart';
import '../../widgets/marca.dart';
import '../auth/bloqueo_screen.dart';
import '../clientes/clientes_screen.dart';
import '../cobros/cobros_screen.dart';
import '../inicio/inicio_screen.dart';
import '../mas/mas_screen.dart';
import '../pedidos/pedidos_screen.dart';
import '../proveedor/proveedor_screen.dart';
import '../ventas/ventas_screen.dart';

/// Barra fija con 6 botones (abajo en el celular, a la izquierda en la computadora).
/// El vendedor solo ve Pedidos, Clientes y su cuenta.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Pestaña activa. Se puede cambiar desde cualquier pantalla (ej: un aviso de Inicio → Proveedor).
  static final tab = ValueNotifier<int>(0);

  static void irA(BuildContext context, int index) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    tab.value = index;
  }

  // Pestañas del administrador.
  static const inicio = 0;
  static const pedidos = 1;
  static const ventas = 2;
  static const proveedor = 3;
  static const cobros = 4;
  static const mas = 5;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _Destino {
  const _Destino(this.label, this.icon, this.selected, this.pantalla);
  final String label;
  final IconData icon;
  final IconData selected;
  final Widget pantalla;
}

class _HomeShellState extends State<HomeShell> {
  static const _admin = [
    _Destino('Inicio', Icons.space_dashboard_outlined, Icons.space_dashboard, InicioScreen()),
    _Destino('Pedidos', Icons.receipt_long_outlined, Icons.receipt_long, PedidosScreen()),
    _Destino('Ventas', Icons.point_of_sale_outlined, Icons.point_of_sale, VentasScreen()),
    _Destino('Proveedor', Icons.local_shipping_outlined, Icons.local_shipping, ProveedorScreen()),
    _Destino('Cobros', Icons.payments_outlined, Icons.payments, CobrosScreen()),
    _Destino('Más', Icons.more_horiz, Icons.more_horiz, MasScreen()),
  ];
  static const _vendedor = [
    _Destino('Pedidos', Icons.receipt_long_outlined, Icons.receipt_long, PedidosScreen()),
    _Destino('Clientes', Icons.storefront_outlined, Icons.storefront, ClientesScreen()),
    _Destino('Mi cuenta', Icons.account_circle_outlined, Icons.account_circle, MasScreen()),
  ];

  @override
  void initState() {
    super.initState();
    // Cada vez que alguien entra, arranca en la primera pestaña.
    HomeShell.tab.value = 0;
    HomeShell.tab.addListener(_onTab);
    _sincronizacion = context.read<SincronizacionProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Sube lo que quedó sin señal y reserva números de pedido.
      _sincronizacion.iniciar();
      context.read<NegocioProvider>().cargar();
      if (context.read<AuthProvider>().consumirRecienIngreso()) ofrecerBiometria(context);
    });
  }

  void _onTab() => setState(() {});

  late final SincronizacionProvider _sincronizacion;

  @override
  void dispose() {
    _sincronizacion.detener();
    HomeShell.tab.removeListener(_onTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esAdmin = context.select<AuthProvider, bool>((a) => a.esAdmin);
    final destinos = esAdmin ? _admin : _vendedor;
    final index = HomeShell.tab.value.clamp(0, destinos.length - 1);
    final body = IndexedStack(index: index, children: [for (final d in destinos) d.pantalla]);
    void ir(int i) => HomeShell.tab.value = i;

    if (isWide(context)) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: ir,
              labelType: NavigationRailLabelType.all,
              minWidth: 96,
              leading: const Padding(
                padding: EdgeInsets.fromLTRB(8, 20, 8, 28),
                child: SizedBox(width: 84, child: Marca(size: 22, color: Colors.white)),
              ),
              destinations: [
                for (final d in destinos)
                  NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: Text(d.label)),
              ],
            ),
            Expanded(child: Column(children: [Expanded(child: body), const FranjaSincronizacion()])),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const FranjaSincronizacion(),
        NavigationBar(
          selectedIndex: index,
          onDestinationSelected: ir,
          destinations: [
            for (final d in destinos) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
          ],
        ),
      ]),
    );
  }
}
