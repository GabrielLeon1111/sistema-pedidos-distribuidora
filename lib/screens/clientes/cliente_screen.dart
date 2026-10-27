import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cliente.dart';
import '../../models/pago.dart';
import '../../models/pedido.dart';
import '../../models/venta.dart';
import '../../providers/auth_provider.dart';
import '../../providers/negocio_provider.dart';
import '../../repositories/cliente_repository.dart';
import '../../repositories/cobro_repository.dart';
import '../../repositories/pedido_repository.dart';
import '../../repositories/venta_repository.dart';
import '../../services/compartir.dart';
import '../../services/mensajes.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/estados.dart';
import '../../widgets/reloading_future.dart';
import '../cobros/pago_sheet.dart';
import '../cobros/recibo_screen.dart';
import '../pedidos/pedido_detalle_screen.dart';
import '../pedidos/pedido_editor_screen.dart';
import '../ventas/venta_screen.dart';
import 'cliente_form.dart';

class _Datos {
  _Datos(this.cliente, this.pedidos, this.rechazos, {this.cuenta, this.ventas = const [], this.pagos = const []});
  final Cliente cliente;
  final List<Pedido> pedidos;
  final List<Rechazo> rechazos;
  final CuentaCliente? cuenta;
  final List<Venta> ventas;
  final List<Pago> pagos;
}

/// Ficha del local: datos para facturar, pedidos, rechazos y (para el
/// administrador) lo que compró, pagó y debe.
class ClienteScreen extends StatelessWidget {
  const ClienteScreen({super.key, required this.id});
  final String id;

  Future<_Datos> _cargar(BuildContext context) async {
    final esAdmin = context.read<AuthProvider>().esAdmin;
    final clientes = context.read<ClienteRepository>();
    final pedidosRepo = context.read<PedidoRepository>();
    final cobros = context.read<CobroRepository>();
    final ventas = context.read<VentaRepository>();
    final c = await clientes.obtener(id);
    if (c == null) throw StateError('cliente');
    final pedidos = await pedidosRepo.listar(clienteId: id);
    final rechazos = await clientes.rechazos(id);
    if (!esAdmin) return _Datos(c, pedidos, rechazos);
    return _Datos(
      c,
      pedidos,
      rechazos,
      cuenta: await cobros.cuenta(id),
      ventas: await ventas.listar(clienteId: id),
      pagos: await cobros.pagos(clienteId: id),
    );
  }

  @override
  Widget build(BuildContext context) => ReloadingFuture<_Datos>(
        titulo: 'Local',
        contexto: 'cliente',
        load: () => _cargar(context),
        builder: (context, d, reload) {
          final c = d.cliente;
          final cuenta = d.cuenta;
          final negocio = context.watch<NegocioProvider>().negocio.nombre;
          final whatsapp = telefonoWhatsapp(c.telefono);
          return DefaultTabController(
            length: cuenta == null ? 2 : 4,
            child: Scaffold(
              appBar: AppBar(
                title: Text(c.nombre),
                actions: [IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => editarCliente(context, c))],
                bottom: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    const Tab(text: 'Datos'),
                    if (cuenta != null) const Tab(text: 'Facturas'),
                    if (cuenta != null) const Tab(text: 'Pagos'),
                    Tab(text: 'Pedidos (${d.pedidos.length})'),
                  ],
                ),
              ),
              floatingActionButton: FloatingActionButton.extended(
                heroTag: 'nuevo-pedido-cliente',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PedidoEditorScreen())),
                icon: const Icon(Icons.add),
                label: const Text('Nota de pedido'),
              ),
              body: TabBarView(children: [
                ListView(
                  padding: EdgeInsets.fromLTRB(margenLateral(context), 12, margenLateral(context), 100),
                  children: [
                    Cuerpo(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (cuenta != null) ...[
                          GrillaTarjetas(children: [
                            StatCard(
                              label: 'Debe',
                              value: gs(cuenta.deuda),
                              detail: cuenta.deudaDesde == null ? 'Al día' : 'Desde ${antiguedadTexto(cuenta.diasDeuda!)}',
                              icon: Icons.account_balance_wallet_outlined,
                              highlight: cuenta.deuda > 0,
                            ),
                            StatCard(label: 'Compró', value: gs(cuenta.totalComprado), icon: Icons.shopping_bag_outlined),
                            StatCard(label: 'Pagó', value: gs(cuenta.totalPagado), icon: Icons.payments_outlined),
                            if (cuenta.aFavor > 0) StatCard(label: 'A favor / señas', value: gs(cuenta.aFavor), icon: Icons.savings_outlined),
                          ]),
                          const SizedBox(height: 10),
                          if (cuenta.deuda > 0)
                            Row(children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => registrarPago(context, clienteId: c.id, clienteNombre: c.nombre, maximo: cuenta.deuda),
                                  icon: const Icon(Icons.payments_outlined),
                                  label: const Text('Registrar pago'),
                                ),
                              ),
                              if (whatsapp != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.whatsapp, side: const BorderSide(color: AppColors.whatsapp)),
                                    onPressed: () => abrirWhatsapp(whatsapp, texto: mensajeDeuda(c.contacto ?? c.nombre, cuenta.deuda, negocio)),
                                    icon: const Icon(Icons.chat_outlined),
                                    label: const Text('Recordar'),
                                  ),
                                ),
                              ],
                            ]),
                        ],
                        if (d.rechazos.isNotEmpty) ...[
                          const SectionTitle('Historial de rechazos'),
                          Card(
                            child: Column(children: [
                              for (final r in d.rechazos)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.do_not_disturb_alt, color: AppColors.red),
                                  title: Text(r.detalle),
                                  subtitle: Text('${fechaCorta.format(r.fecha)}${r.pedidoNumero > 0 ? ' · Pedido N° ${nroDoc(r.pedidoNumero)}' : ''}'),
                                  trailing: r.monto > 0 ? Text(gs(r.monto)) : null,
                                ),
                            ]),
                          ),
                        ],
                        const SectionTitle('Datos para facturar'),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(children: [
                              KeyValueRow('Local', c.nombre),
                              KeyValueRow('Razón social', c.razonSocial ?? '—'),
                              KeyValueRow('RUC', c.ruc ?? '—'),
                              KeyValueRow('Dirección', c.direccion ?? '—'),
                              KeyValueRow('Teléfono', c.telefono ?? '—'),
                              KeyValueRow('Contacto', c.contacto ?? '—'),
                              if (c.notas != null) KeyValueRow('Notas', c.notas!),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
                if (cuenta != null)
                  _Lista(
                    vacio: 'Todavía no tiene facturas',
                    hijos: [
                      for (final v in d.ventas)
                        ListTile(
                          title: Text(v.factura?.numeroCompleto ?? 'Nota N° ${nroDoc(v.numero)}'),
                          subtitle: Text('${fechaCorta.format(v.fecha)} · ${gs(v.total)}${v.saldo > 0 ? ' · debe ${gs(v.saldo)}' : ''}'),
                          trailing: PillPago(v.estadoPago),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VentaScreen(id: v.id))),
                        ),
                    ],
                  ),
                if (cuenta != null)
                  _Lista(
                    vacio: 'Todavía no hay pagos',
                    hijos: [
                      for (final p in d.pagos)
                        ListTile(
                          title: Text('${gs(p.monto)} · ${metodoPagoTexto(p.metodo)}'),
                          subtitle: Text('Recibo N° ${nroDoc(p.numero)} · ${fechaCorta.format(p.fecha)}${p.esSena ? ' · seña' : ''}${p.anulado ? ' · anulado' : ''}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReciboScreen(id: p.id))),
                        ),
                    ],
                  ),
                _Lista(
                  vacio: 'Todavía no tiene pedidos',
                  hijos: [
                    for (final p in d.pedidos)
                      ListTile(
                        title: Text('Pedido N° ${nroDoc(p.numero)} · ${gs(p.total)}'),
                        subtitle: Text(fechaHora.format(p.fecha)),
                        trailing: PillPedido(p),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoDetalleScreen(id: p.id))),
                      ),
                  ],
                ),
              ]),
            ),
          );
        },
      );
}

class _Lista extends StatelessWidget {
  const _Lista({required this.hijos, required this.vacio});
  final List<Widget> hijos;
  final String vacio;

  @override
  Widget build(BuildContext context) {
    if (hijos.isEmpty) return EmptyState(icon: Icons.inbox_outlined, title: vacio);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(margenLateral(context), 10, margenLateral(context), 100),
      itemCount: hijos.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (_, i) => Cuerpo(child: hijos[i]),
    );
  }
}
