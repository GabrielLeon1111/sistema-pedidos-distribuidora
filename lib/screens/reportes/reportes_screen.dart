import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/reportes.dart';
import '../../providers/negocio_provider.dart';
import '../../repositories/reporte_repository.dart';
import '../../services/compartir.dart';
import '../../services/reporte_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/periodo.dart';
import '../../widgets/reloading_future.dart';

/// Reportes del período: vendido, pagado al proveedor, ganancia, gastos,
/// margen por producto y por local, cobrado, falta cobrar y rechazos.
class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  PeriodoElegido _periodo = PeriodoElegido.de(TipoPeriodo.mes);

  String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} %';

  Future<void> _exportar(Reporte r, bool excel) async {
    final repo = context.read<ReporteRepository>();
    final negocio = context.read<NegocioProvider>().negocio;
    await runSafe(context, 'exportar', () async {
      if (excel) {
        final ventas = await repo.ventas(r.desde, r.hasta);
        await guardarArchivo(reporteExcel(r, ventas), nombreReporte(r, 'xlsx'), esPdf: false);
      } else {
        await guardarArchivo(await reportePdf(r, negocio), nombreReporte(r, 'pdf'));
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reportes')),
        body: ReloadingFuture<Reporte>(
          key: ValueKey('${_periodo.desde}${_periodo.hasta}'),
          contexto: 'reporte',
          load: () => context.read<ReporteRepository>().reporte(_periodo.desde, _periodo.hasta),
          builder: (context, r, reload) => ListView(
            padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 40),
            children: [
              Cuerpo(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SelectorPeriodo(valor: _periodo, onChanged: (p) => setState(() => _periodo = p)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => _exportar(r, false), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(onPressed: () => _exportar(r, true), icon: const Icon(Icons.table_view_outlined), label: const Text('Excel'))),
                  ]),
                  const SectionTitle('Resultado'),
                  GrillaTarjetas(children: [
                    StatCard(label: 'Vendido', value: gs(r.vendido), detail: '${r.notas} facturas', icon: Icons.point_of_sale),
                    StatCard(label: 'Ganancia', value: gs(r.ganancia), detail: 'Margen ${_pct(r.margen)}', icon: Icons.trending_up),
                    StatCard(label: 'Gastos', value: gs(r.gastos), icon: Icons.receipt_long_outlined),
                    StatCard(label: 'Ganancia real', value: gs(r.gananciaReal), detail: 'Ganancia − gastos − pérdidas', icon: Icons.savings_outlined, highlight: true),
                  ]),
                  const SectionTitle('Plata'),
                  GrillaTarjetas(children: [
                    StatCard(
                      label: 'Pagado al proveedor',
                      value: gs(r.totalPagadoProveedores),
                      detail: r.comprasPropias > 0 ? 'Incluye compras para stock ${gs(r.comprasPropias)}' : null,
                      icon: Icons.local_shipping_outlined,
                    ),
                    StatCard(label: 'Cobrado', value: gs(r.cobrado), icon: Icons.payments_outlined),
                    StatCard(label: 'Falta cobrar', value: gs(r.faltaCobrar), detail: 'De las facturas del período', icon: Icons.account_balance_wallet_outlined),
                    StatCard(label: 'Perdido por rechazos', value: gs(r.perdidoRechazos), detail: '${r.cantidadRechazos} rechazos', icon: Icons.do_not_disturb_alt),
                    if (r.perdidas > 0) StatCard(label: 'Pérdidas de stock', value: gs(r.perdidas), icon: Icons.broken_image_outlined),
                  ]),
                  const SectionTitle('Por producto'),
                  if (r.productos.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Sin ventas en el período.', style: TextStyle(color: AppColors.muted))))
                  else
                    Card(
                      child: Column(children: [
                        for (final p in r.productos)
                          ListTile(
                            dense: true,
                            title: Text(p.nombre),
                            subtitle: Text('${cantidad(p.cantidad)} ${unidadPlural(p.unidad, p.cantidad)} · vendido ${gs(p.vendido)} · margen ${_pct(p.margen)}'),
                            trailing: Text(gs(p.ganancia), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.green)),
                          ),
                      ]),
                    ),
                  const SectionTitle('Por local'),
                  if (r.locales.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Sin movimientos en el período.', style: TextStyle(color: AppColors.muted))))
                  else
                    Card(
                      child: Column(children: [
                        for (final l in r.locales)
                          ListTile(
                            dense: true,
                            title: Text(l.nombre),
                            subtitle: Text('Vendido ${gs(l.vendido)} · margen ${_pct(l.margen)} · cobrado ${gs(l.cobrado)}'
                                '${l.saldo > 0 ? ' · debe ${gs(l.saldo)}' : ''}${l.rechazos > 0 ? ' · ${l.rechazos} rechazos' : ''}'),
                            trailing: Text(gs(l.ganancia), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.green)),
                          ),
                      ]),
                    ),
                  if (r.gastosPorCategoria.isNotEmpty) ...[
                    const SectionTitle('Gastos por categoría'),
                    Card(
                      child: Column(children: [
                        for (final g in r.gastosPorCategoria)
                          ListTile(dense: true, title: Text(g.categoria), subtitle: Text('${g.cantidad} gastos'), trailing: Text(gs(g.monto), style: const TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                    ),
                  ],
                ]),
              ),
            ],
          ),
        ),
      );
}
