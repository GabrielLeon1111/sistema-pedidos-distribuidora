import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/reportes.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/reporte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import '../shell/home_shell.dart';

/// Panel: cuánto se vendió y ganó, quién debe y qué hay pendiente.
class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nombre = context.select<AuthProvider, String>((a) => a.nombre);
    return Scaffold(
      body: SafeArea(
        child: ReloadingFuture<Panel>(
          contexto: 'panel',
          load: () => context.read<ReporteRepository>().panel(),
          builder: (context, p, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: EdgeInsets.fromLTRB(margenLateral(context), 16, margenLateral(context), 32),
              children: [
                Cuerpo(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Bienvenido $nombre', style: Theme.of(context).textTheme.headlineSmall),
                      Text(_capital(fechaLarga.format(DateTime.now())), style: const TextStyle(color: AppColors.muted, fontSize: 15)),
                      const SizedBox(height: 14),
                      if (p.avisos.hayAlgo) ...[_Avisos(p.avisos), const SizedBox(height: 4)],
                      const SectionTitle('Hoy'),
                      GrillaTarjetas(children: [
                        StatCard(label: 'Vendido hoy', value: gs(p.hoy.vendido), detail: '${p.hoy.notas} notas de venta', icon: Icons.point_of_sale),
                        StatCard(label: 'Ganancia hoy', value: gs(p.hoy.ganancia), icon: Icons.trending_up, highlight: true),
                        StatCard(label: 'Cobrado hoy', value: gs(p.cobradoHoy), icon: Icons.payments_outlined),
                        StatCard(
                          label: 'Te deben',
                          value: gs(p.totalDeuda),
                          detail: '${p.localesQueDeben} ${p.localesQueDeben == 1 ? 'local' : 'locales'}',
                          icon: Icons.account_balance_wallet_outlined,
                          onTap: () => HomeShell.irA(context, HomeShell.cobros),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      // Lo que suman las notas levantadas (sin descontar nada).
                      StatCard(
                        label: 'Total en pedidos levantados',
                        value: gs(p.totalPendiente),
                        detail: p.notasPendientes == 1 ? '1 nota de pedido sin entregar' : '${p.notasPendientes} notas de pedido sin entregar',
                        icon: Icons.receipt_long_outlined,
                        onTap: () => HomeShell.irA(context, HomeShell.pedidos),
                      ),
                      const SizedBox(height: 10),
                      // Lo que se gana (ya descontado lo que cuesta cada producto) si se entregan todas las notas.
                      StatCard(
                        label: 'Ganancia si se concretan todos los pedidos',
                        value: gs(p.pendiente.ganancia),
                        detail: p.notasPendientes == 1 ? '1 nota de pedido por concretar' : '${p.notasPendientes} notas de pedido por concretar',
                        icon: Icons.request_quote_outlined,
                        highlight: true,
                        onTap: () => HomeShell.irA(context, HomeShell.pedidos),
                      ),
                      const SectionTitle('Ventas y ganancia'),
                      _TablaPeriodos(p),
                      const SectionTitle('Últimos 12 meses'),
                      _Barras(p.meses),
                      const SectionTitle('Más vendidos del mes'),
                      _Ranking(p.masVendidos, porGanancia: false),
                      const SectionTitle('Los que más ganancia dejan (mes)'),
                      _Ranking(p.masGanancia, porGanancia: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Avisos extends StatelessWidget {
  const _Avisos(this.a);
  final Avisos a;

  @override
  Widget build(BuildContext context) {
    Widget aviso(int n, String texto, IconData icon, Color color, Color fondo, int tab) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: fondo,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => HomeShell.irA(context, tab),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 10),
                  Expanded(child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
                  Icon(Icons.chevron_right, color: color),
                ]),
              ),
            ),
          ),
        );
    return Column(children: [
      if (a.esperandoConfirmacion > 0)
        aviso(a.esperandoConfirmacion, '${a.esperandoConfirmacion} pedidos esperando que el local confirme lo que llegó',
            Icons.hourglass_top_rounded, AppColors.orange, AppColors.orangeSoft, HomeShell.pedidos),
      if (a.sinEntregar > 0)
        aviso(a.sinEntregar,
            '${a.sinEntregar} pedidos sin entregar${a.entregasAtrasadas > 0 ? ' (${a.entregasAtrasadas} atrasados)' : ''}',
            Icons.local_shipping_outlined, AppColors.blue, AppColors.blueSoft, HomeShell.pedidos),
      if (a.sinRecibir > 0)
        aviso(a.sinRecibir, '${a.sinRecibir} pedidos al proveedor sin recibir', Icons.inventory_outlined, AppColors.primary,
            AppColors.primarySoft, HomeShell.proveedor),
      if (a.sinPedir > 0)
        aviso(a.sinPedir, '${a.sinPedir} notas de pedido para pedir al proveedor', Icons.playlist_add_check, AppColors.primary,
            AppColors.primarySoft, HomeShell.proveedor),
      if (a.stockBajo > 0)
        aviso(a.stockBajo, '${a.stockBajo} productos por agotarse en el stock', Icons.warning_amber_rounded, AppColors.red, AppColors.redSoft,
            HomeShell.mas),
    ]);
  }
}

class _TablaPeriodos extends StatelessWidget {
  const _TablaPeriodos(this.p);
  final Panel p;

  @override
  Widget build(BuildContext context) {
    final v = p.variacionMes;
    Widget fila(String nombre, Periodo x, {Widget? extra}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                ?extra,
              ]),
            ),
            Expanded(
              flex: 3,
              child: Text(gs(x.vendido), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            Expanded(
              flex: 3,
              child: Text(gs(x.ganancia),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(children: [
          const Row(children: [
            Expanded(flex: 3, child: SizedBox()),
            Expanded(flex: 3, child: Text('Vendido', textAlign: TextAlign.right, style: TextStyle(color: AppColors.muted, fontSize: 12.5))),
            Expanded(flex: 3, child: Text('Ganancia', textAlign: TextAlign.right, style: TextStyle(color: AppColors.muted, fontSize: 12.5))),
          ]),
          fila('Hoy', p.hoy),
          const Divider(),
          fila('Semana', p.semana),
          const Divider(),
          fila(
            'Mes',
            p.mes,
            extra: v == null
                ? null
                : Text(
                    '${v >= 0 ? '▲' : '▼'} ${NumberFormat('#,##0.#', 'es').format(v.abs())} % vs. mes anterior',
                    style: TextStyle(fontSize: 12, color: v >= 0 ? AppColors.green : AppColors.red, fontWeight: FontWeight.w600),
                  ),
          ),
          const Divider(),
          fila('Año', p.anio),
        ]),
      ),
    );
  }
}

class _Barras extends StatelessWidget {
  const _Barras(this.meses);
  final List<(DateTime, int)> meses;

  @override
  Widget build(BuildContext context) {
    final max = meses.fold<int>(0, (m, e) => e.$2 > m ? e.$2 : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
        child: SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < meses.length; i++)
                Expanded(
                  child: Tooltip(
                    message: '${mesAnio.format(meses[i].$1)}: ${gs(meses[i].$2)}',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: max == 0 ? 2 : (110 * meses[i].$2 / max).clamp(2, 110).toDouble(),
                          decoration: BoxDecoration(
                            color: i == meses.length - 1 ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(child: Text(mesCorto.format(meses[i].$1), style: const TextStyle(fontSize: 11, color: AppColors.muted))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ranking extends StatelessWidget {
  const _Ranking(this.items, {required this.porGanancia});
  final List<ProductoRanking> items;
  final bool porGanancia;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Todavía no hay ventas este mes.', style: TextStyle(color: AppColors.muted))));
    }
    return Card(
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(),
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primarySoft,
              child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 13)),
            ),
            title: Text(items[i].nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${cantidad(items[i].cantidad)} ${unidadPlural(items[i].unidad, items[i].cantidad)}'
              '${items[i].margen == null ? '' : ' · margen ${NumberFormat('#,##0.#', 'es').format(items[i].margen)} %'}',
            ),
            trailing: Text(
              gs(porGanancia ? items[i].ganancia : items[i].vendido),
              style: TextStyle(fontWeight: FontWeight.w800, color: porGanancia ? AppColors.green : AppColors.ink),
            ),
          ),
        ],
      ]),
    );
  }
}
