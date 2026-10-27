import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/usuario_repository.dart';
import '../../security/claves.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../clientes/clientes_screen.dart';
import '../gastos/gastos_screen.dart';
import '../historial/historial_screen.dart';
import '../inventario/inventario_screen.dart';
import '../negocio/negocio_screen.dart';
import '../negocio/proveedores_screen.dart';
import '../negocio/timbrado_screen.dart';
import '../reportes/reportes_screen.dart';
import '../usuarios/usuarios_screen.dart';

/// Inventario, clientes, gastos, reportes, historial, usuarios, datos del negocio
/// y la cuenta de quien usa la app.
class MasScreen extends StatelessWidget {
  const MasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    void ir(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    Widget item(IconData icon, String titulo, String sub, Widget destino) => ListTile(
          leading: CircleAvatar(backgroundColor: AppColors.primarySoft, child: Icon(icon, color: AppColors.primary)),
          title: Text(titulo),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => ir(destino),
        );

    return Scaffold(
      appBar: AppBar(title: Text(auth.esAdmin ? 'Más' : 'Mi cuenta')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 32),
        children: [
          Cuerpo(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (auth.esAdmin) ...[
                const SectionTitle('Negocio'),
                Card(
                  child: Column(children: [
                    item(Icons.inventory_2_outlined, 'Inventario', 'Stock, compras, pérdidas y movimientos', const InventarioScreen()),
                    const Divider(),
                    item(Icons.storefront_outlined, 'Clientes', 'Locales y sus cuentas', const ClientesScreen()),
                    const Divider(),
                    item(Icons.receipt_long_outlined, 'Gastos', 'Combustible, flete, viáticos…', const GastosScreen()),
                    const Divider(),
                    item(Icons.bar_chart_rounded, 'Reportes', 'Ventas, ganancia y margen (PDF y Excel)', const ReportesScreen()),
                    const Divider(),
                    item(Icons.history, 'Historial', 'Documentos y quién hizo cada cambio', const HistorialScreen()),
                  ]),
                ),
                const SectionTitle('Configuración'),
                Card(
                  child: Column(children: [
                    item(Icons.verified_outlined, 'Timbrado', 'Datos del timbrado para las facturas', const TimbradoScreen()),
                    const Divider(),
                    item(Icons.business_outlined, 'Datos del negocio', 'Nombre, RUC, logo y datos de la factura', const NegocioScreen()),
                    const Divider(),
                    item(Icons.local_shipping_outlined, 'Proveedores', 'A quién le pedís la mercadería', const ProveedoresScreen()),
                    const Divider(),
                    item(Icons.group_outlined, 'Usuarios', 'Vendedores y administradores', const UsuariosScreen()),
                  ]),
                ),
              ] else ...[
                const SectionTitle('Documentos'),
                Card(child: item(Icons.history, 'Mis notas de pedido', 'Volver a abrirlas, enviarlas o descargarlas', const HistorialScreen())),
              ],
              const SectionTitle('Mi cuenta'),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const CircleAvatar(backgroundColor: AppColors.accentSoft, child: Icon(Icons.person, color: AppColors.ink)),
                    title: Text(auth.nombre),
                    subtitle: Text('${auth.usuario?.usuario ?? ''} · ${auth.usuario?.rolTexto ?? ''}'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.password_outlined),
                    title: const Text('Cambiar mi contraseña'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _cambiarClave(context),
                  ),
                  const Divider(),
                  const _Huella(),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: AppColors.red),
                    title: const Text('Cerrar sesión', style: TextStyle(color: AppColors.red)),
                    onTap: () async {
                      final ok = await confirmar(context, titulo: '¿Cerrar sesión?', mensaje: 'Para volver a entrar vas a necesitar tu usuario y contraseña.', si: 'Salir');
                      if (ok && context.mounted) context.read<AuthProvider>().salir();
                    },
                  ),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _cambiarClave(BuildContext context) async {
    final actual = TextEditingController();
    final nueva = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cambiar mi contraseña'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: actual,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
              validator: (v) => (v ?? '').isEmpty ? 'Escribí tu contraseña actual' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: nueva, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña nueva'), validator: validarClave),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => form.currentState!.validate() ? Navigator.pop(c, true) : null, child: const Text('Cambiar')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await runSafe(context, 'cambiarClave', () => context.read<UsuarioRepository>().cambiarMiClave(actual.text, nueva.text), ok: 'Contraseña cambiada');
    }
    actual.dispose();
    nueva.dispose();
  }
}

class _Huella extends StatefulWidget {
  const _Huella();

  @override
  State<_Huella> createState() => _HuellaState();
}

class _HuellaState extends State<_Huella> {
  bool? _disponible;
  bool _activa = false;

  @override
  void initState() {
    super.initState();
    final b = context.read<AuthProvider>().biometria;
    Future.wait([b.disponible(), b.activada()]).then((r) {
      if (mounted) {
        setState(() {
          _disponible = r[0];
          _activa = r[1];
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_disponible != true) {
      return const ListTile(
        leading: Icon(Icons.fingerprint),
        title: Text('Huella / Face ID'),
        subtitle: Text('Este equipo no tiene huella configurada'),
      );
    }
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: const Text('Entrar con huella / Face ID'),
      value: _activa,
      onChanged: (v) async {
        await context.read<AuthProvider>().biometria.activar(v);
        if (mounted) setState(() => _activa = v);
      },
    );
  }
}
