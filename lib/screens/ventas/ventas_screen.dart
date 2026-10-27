import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/venta.dart';
import '../../repositories/venta_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/estados.dart';
import '../../widgets/reloading_future.dart';
import 'venta_directa_screen.dart';
import 'venta_screen.dart';

enum _Filtro {
  todas('Todas'),
  debe('Con saldo'),
  pagadas('Pagadas'),
  anuladas('Anuladas');

  const _Filtro(this.texto);
  final String texto;
}

/// Ventas: las facturas emitidas (por entrega de pedidos o venta directa) y
/// el acceso a vender directo desde el stock.
class VentasScreen extends StatefulWidget {
  const VentasScreen({super.key});

  @override
  State<VentasScreen> createState() => _VentasScreenState();
}

class _VentasScreenState extends State<VentasScreen> {
  _Filtro _filtro = _Filtro.todas;
  String _q = '';

  bool _pasa(Venta v) {
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty &&
        !v.cliente.nombre.toLowerCase().contains(q) &&
        !nroDoc(v.numero).contains(q) &&
        !(v.factura?.numeroCompleto.contains(q) ?? false)) {
      return false;
    }
    return switch (_filtro) {
      _Filtro.todas => true,
      _Filtro.debe => !v.anulada && v.saldo > 0,
      _Filtro.pagadas => !v.anulada && v.saldo == 0,
      _Filtro.anuladas => v.anulada,
    };
  }

  Future<void> _vender() => Navigator.push(context, MaterialPageRoute(builder: (_) => const VentaDirectaScreen()));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ventas')),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'venta-directa',
          onPressed: _vender,
          icon: const Icon(Icons.point_of_sale),
          label: const Text('Venta directa'),
        ),
        body: ReloadingFuture<List<Venta>>(
          contexto: 'ventas',
          load: () => context.read<VentaRepository>().listar(),
          builder: (context, todas, reload) {
            final lista = todas.where(_pasa).toList();
            final hoy = inicioDia(DateTime.now());
            final deHoy = todas.where((v) => !v.anulada && !v.fecha.isBefore(hoy));
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                padding: EdgeInsets.fromLTRB(margenLateral(context), 0, margenLateral(context), 100),
                children: [
                  Cuerpo(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      GrillaTarjetas(children: [
                        StatCard(label: 'Vendido hoy', value: gs(deHoy.fold(0, (s, v) => s + v.total)), detail: '${deHoy.length} facturas', highlight: true),
                        StatCard(
                          label: 'Falta cobrar',
                          value: gs(todas.fold(0, (s, v) => s + v.saldo)),
                          detail: '${todas.where((v) => v.saldo > 0).length} facturas con saldo',
                        ),
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar local o número de factura'),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final f in _Filtro.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(label: Text(f.texto), selected: _filtro == f, onSelected: (_) => setState(() => _filtro = f)),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      if (lista.isEmpty)
                        EmptyState(
                          icon: Icons.point_of_sale_outlined,
                          title: todas.isEmpty ? 'Todavía no hay ventas' : 'No hay ventas con ese filtro',
                          message: todas.isEmpty ? 'Se generan al entregar un pedido o con una venta directa desde el stock.' : null,
                        )
                      else
                        for (final v in lista) ...[_TarjetaVenta(v), const SizedBox(height: 8)],
                    ]),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class _TarjetaVenta extends StatelessWidget {
  const _TarjetaVenta(this.v);
  final Venta v;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VentaScreen(id: v.id))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(v.cliente.nombre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Text(
                  gs(v.total),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    decoration: v.anulada ? TextDecoration.lineThrough : null,
                    color: v.anulada ? AppColors.muted : null,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                [
                  if (v.factura != null) 'Factura ${v.factura!.numeroCompleto}' else 'N° ${nroDoc(v.numero)}',
                  fechaHora.format(v.fecha),
                  v.pedidoNumero == null ? 'Venta directa' : 'Pedido N° ${nroDoc(v.pedidoNumero!)}',
                ].join(' · '),
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                PillPago(v.estadoPago),
                if (!v.anulada && v.saldo > 0) Pill('Debe ${gs(v.saldo)}', color: AppColors.red),
                if (v.entregaParcial) const Pill('Entrega parcial', color: AppColors.orange),
              ]),
            ]),
          ),
        ),
      );
}
