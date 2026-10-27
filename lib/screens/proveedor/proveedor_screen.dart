import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/consolidado.dart';
import '../../models/pedido.dart';
import '../../providers/refresh_bus.dart';
import '../../providers/sincronizacion_provider.dart';
import '../../repositories/proveedor_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import 'consolidado_screen.dart';
import 'recepcion_screen.dart';

/// Consolidado del día (hoja para el proveedor) y recepción de mercadería.
class ProveedorScreen extends StatelessWidget {
  const ProveedorScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Proveedor'),
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [Tab(text: 'Pedir'), Tab(text: 'Por recibir'), Tab(text: 'Recibidos')],
            ),
          ),
          body: const TabBarView(children: [_Pedir(), _Hojas(recibidos: false), _Hojas(recibidos: true)]),
        ),
      );
}

class _Pedir extends StatefulWidget {
  const _Pedir();

  @override
  State<_Pedir> createState() => _PedirState();
}

class _PedirState extends State<_Pedir> {
  Set<String>? _elegidos;
  bool _armando = false;

  /// La misma en cada reintento: si se corta la señal, la hoja no se arma dos veces.
  final _clave = ClaveOperacion();
  final _claveLista = ClaveOperacion();

  Future<void> _armar(List<Pedido> pedidos) async {
    final ids = _elegidos ?? {for (final p in pedidos) p.id};
    if (ids.isEmpty) return showSnack(context, 'Elegí al menos un pedido.', error: true);
    setState(() => _armando = true);
    try {
      final hojas = await context.read<ProveedorRepository>().crearConsolidados(ids.toList(), clave: _clave.valor);
      // Salió bien: la próxima hoja que se arme en esta pantalla es otra operación.
      _clave.renovar();
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      setState(() => _elegidos = null);
      if (hojas.length == 1) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ConsolidadoScreen(id: hojas.single.id)));
      } else {
        showSnack(context, 'Se armaron ${hojas.length} hojas, una por proveedor. Están en "Por recibir".');
      }
    } catch (e) {
      registrarError('consolidar', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _armando = false);
    }
  }

  /// Lista de compras: todas las notas pendientes, para ir a comprar uno mismo.
  Future<void> _listaCompras(List<Pedido> pedidos) async {
    final ok = await confirmar(
      context,
      titulo: '¿Armar tu lista de compras?',
      mensaje: 'Va todo lo de las ${pedidos.length} notas pendientes, separado por categoría. '
          'Después vas marcando lo que compraste y lo que no.',
      si: 'Armar lista',
    );
    if (!ok || !mounted) return;
    setState(() => _armando = true);
    try {
      final lista = await context.read<ProveedorRepository>().crearListaCompras([for (final p in pedidos) p.id], clave: _claveLista.valor);
      _claveLista.renovar();
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      setState(() => _elegidos = null);
      Navigator.push(context, MaterialPageRoute(builder: (_) => RecepcionScreen(consolidado: lista)));
    } catch (e) {
      registrarError('listaCompras', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _armando = false);
    }
  }

  @override
  Widget build(BuildContext context) => ReloadingFuture<List<Pedido>>(
        contexto: 'paraConsolidar',
        load: () => context.read<ProveedorRepository>().pedidosParaConsolidar(),
        builder: (context, pedidos, reload) {
          if (pedidos.isEmpty) {
            return const EmptyState(
              icon: Icons.playlist_add_check,
              title: 'No hay pedidos para pedir',
              message: 'Cuando cargues notas de pedido, aparecen acá para armar la hoja del proveedor.',
            );
          }
          final elegidos = _elegidos ?? {for (final p in pedidos) p.id};
          // Vista previa: cantidades por producto de los pedidos elegidos.
          final suma = <String, (String, String, double, double)>{};
          for (final p in pedidos.where((p) => elegidos.contains(p.id))) {
            for (final l in p.lineasAProveedor) {
              // Cada forma de venta por separado (3 docenas y 5 unidades no se suman).
              final k = '${l.productoId ?? l.descripcion.toLowerCase()}|${l.unidad}';
              final x = suma[k];
              suma[k] = (l.descripcion, l.unidad, (x?.$3 ?? 0) + l.cantidad, l.factor);
            }
          }
          final productos = suma.values.toList()..sort((a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
          return Column(children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(margenLateral(context), 8, margenLateral(context), 24),
                  children: [
                    Cuerpo(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        // Lo levantado sin señal todavía no está en el servidor: no entra en la hoja.
                        if (context.watch<SincronizacionProvider>().pendientes > 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Aviso(
                              'En este teléfono hay pedidos sin sincronizar: no van a entrar en la hoja. '
                              'Esperá a que se suban (con señal se suben solos) antes de armarla.',
                              icon: Icons.cloud_upload_outlined,
                            ),
                          ),
                        SectionTitle(
                          'Pedidos (${elegidos.length} de ${pedidos.length})',
                          trailing: TextButton(
                            onPressed: () => setState(() => _elegidos = elegidos.length == pedidos.length ? {} : {for (final p in pedidos) p.id}),
                            child: Text(elegidos.length == pedidos.length ? 'Ninguno' : 'Todos'),
                          ),
                        ),
                        Card(
                          child: Column(children: [
                            for (final p in pedidos)
                              CheckboxListTile(
                                value: elegidos.contains(p.id),
                                onChanged: (v) => setState(() => _elegidos = {...elegidos}..remove(p.id)..addAll(v == true ? [p.id] : [])),
                                title: Text(p.cliente.nombre),
                                subtitle: Text('N° ${nroDoc(p.numero)} · ${fechaHora.format(p.fecha)} · ${p.lineasAProveedor.length} productos'),
                                secondary: Text(gs(p.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                              ),
                          ]),
                        ),
                        SectionTitle('Hoja para el proveedor (${productos.length} productos)'),
                        Card(
                          child: Column(children: [
                            for (final (desc, unidad, q, factor) in productos)
                              ListTile(
                                dense: true,
                                title: Text(desc),
                                trailing: Text('${cantidad(q)} ${textoForma(unidad, factor, q)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FilledButton.icon(
                    onPressed: _armando || elegidos.isEmpty ? null : () => _armar(pedidos),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: Text(_armando ? 'Armando…' : 'Armar hoja para el proveedor'),
                  ),
                  const SizedBox(height: 8),
                  // Voy a comprar yo: lista con todo lo pendiente (sin elegir notas).
                  OutlinedButton.icon(
                    onPressed: _armando ? null : () => _listaCompras(pedidos),
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('Voy a comprar yo: armar mi lista de compras'),
                  ),
                ]),
              ),
            ),
          ]);
        },
      );
}

class _Hojas extends StatelessWidget {
  const _Hojas({required this.recibidos});
  final bool recibidos;

  @override
  Widget build(BuildContext context) => ReloadingFuture<List<Consolidado>>(
        contexto: 'consolidados',
        load: () => context.read<ProveedorRepository>().consolidados(recibidos: recibidos),
        builder: (context, lista, reload) {
          if (lista.isEmpty) {
            return EmptyState(
              icon: recibidos ? Icons.inventory_2_outlined : Icons.local_shipping_outlined,
              title: recibidos ? 'Todavía no se recibió mercadería' : 'No hay pedidos al proveedor esperando',
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(margenLateral(context), 10, margenLateral(context), 24),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final c = lista[i];
                return Cuerpo(
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: recibidos ? AppColors.greenSoft : AppColors.orangeSoft,
                        child: Icon(
                          recibidos ? Icons.inventory_2 : (c.directa ? Icons.shopping_cart : Icons.local_shipping),
                          color: recibidos ? AppColors.green : AppColors.orange,
                        ),
                      ),
                      title: Text('${c.directa ? 'Mi lista de compras' : c.proveedorNombre} · N° ${nroDoc(c.numero)}'),
                      subtitle: Text(
                        '${fechaHora.format(recibidos ? (c.fechaRecepcion ?? c.fecha) : c.fecha)} · ${c.lineas.length} productos · ${c.pedidoIds.length} pedidos'
                        '${recibidos ? ' · pagado ${gs(c.totalCompra)}' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConsolidadoScreen(id: c.id))),
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
}
