import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/pago.dart';
import '../../repositories/cobro_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import '../clientes/cliente_screen.dart';
import 'recibo_screen.dart';

/// Quién debe, desde cuándo, y los últimos pagos.
class CobrosScreen extends StatelessWidget {
  const CobrosScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Cobros'),
            bottom: const TabBar(tabs: [Tab(text: 'Quién debe'), Tab(text: 'Pagos')]),
          ),
          body: const TabBarView(children: [_Deudores(), _Pagos()]),
        ),
      );
}

class _Deudores extends StatefulWidget {
  const _Deudores();

  @override
  State<_Deudores> createState() => _DeudoresState();
}

class _DeudoresState extends State<_Deudores> {
  String _q = '';

  @override
  Widget build(BuildContext context) => ReloadingFuture<List<CuentaCliente>>(
        contexto: 'deudores',
        load: () => context.read<CobroRepository>().cuentas(soloDeudores: true),
        builder: (context, cuentas, reload) {
          final total = cuentas.fold<int>(0, (s, c) => s + c.deuda);
          final lista = cuentas.where((c) => c.cliente.coincide(_q)).toList();
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: EdgeInsets.fromLTRB(margenLateral(context), 12, margenLateral(context), 32),
              children: [
                Cuerpo(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    GrillaTarjetas(children: [
                      StatCard(label: 'Total que te deben', value: gs(total), icon: Icons.account_balance_wallet_outlined, highlight: true),
                      StatCard(label: 'Locales que deben', value: '${cuentas.length}', icon: Icons.storefront_outlined),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar local'),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                    const SizedBox(height: 10),
                    if (lista.isEmpty)
                      const EmptyState(icon: Icons.verified_outlined, title: 'Nadie te debe', message: 'Cuando un local quede debiendo, aparece acá.')
                    else
                      Card(
                        child: Column(children: [
                          for (var i = 0; i < lista.length; i++) ...[
                            if (i > 0) const Divider(),
                            ListTile(
                              title: Text(lista[i].cliente.nombre),
                              subtitle: Text(
                                '${lista[i].notasConSaldo} ${lista[i].notasConSaldo == 1 ? 'factura' : 'facturas'} · '
                                'debe desde ${antiguedadTexto(lista[i].diasDeuda ?? 0)}',
                                style: TextStyle(color: (lista[i].diasDeuda ?? 0) > 30 ? AppColors.red : AppColors.muted),
                              ),
                              trailing: Text(gs(lista[i].deuda), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.red, fontSize: 15)),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClienteScreen(id: lista[i].cliente.id))),
                            ),
                          ],
                        ]),
                      ),
                  ]),
                ),
              ],
            ),
          );
        },
      );
}

class _Pagos extends StatelessWidget {
  const _Pagos();

  @override
  Widget build(BuildContext context) => ReloadingFuture<List<Pago>>(
        contexto: 'pagos',
        load: () => context.read<CobroRepository>().pagos(),
        builder: (context, pagos, reload) {
          if (pagos.isEmpty) return const EmptyState(icon: Icons.payments_outlined, title: 'Todavía no hay pagos');
          final hoy = inicioDia(DateTime.now());
          final deHoy = pagos.where((p) => !p.anulado && !p.fecha.isBefore(hoy)).fold<int>(0, (s, p) => s + p.monto);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: EdgeInsets.fromLTRB(margenLateral(context), 12, margenLateral(context), 32),
              children: [
                Cuerpo(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    StatCard(label: 'Cobrado hoy', value: gs(deHoy), icon: Icons.today_outlined),
                    const SizedBox(height: 10),
                    Card(
                      child: Column(children: [
                        for (var i = 0; i < pagos.length; i++) ...[
                          if (i > 0) const Divider(),
                          ListTile(
                            leading: Icon(pagos[i].anulado ? Icons.block : Icons.receipt_outlined, color: pagos[i].anulado ? AppColors.red : null),
                            title: Text(pagos[i].clienteNombre),
                            subtitle: Text('Recibo N° ${nroDoc(pagos[i].numero)} · ${fechaHora.format(pagos[i].fecha)} · '
                                '${metodoPagoTexto(pagos[i].metodo)}${pagos[i].esSena ? ' · seña' : ''}'),
                            trailing: Text(
                              gs(pagos[i].monto),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                decoration: pagos[i].anulado ? TextDecoration.lineThrough : null,
                                color: pagos[i].anulado ? AppColors.muted : AppColors.green,
                              ),
                            ),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReciboScreen(id: pagos[i].id))),
                          ),
                        ],
                      ]),
                    ),
                  ]),
                ),
              ],
            ),
          );
        },
      );
}
