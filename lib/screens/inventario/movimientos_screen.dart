import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/movimiento.dart';
import '../../repositories/inventario_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import '../../widgets/tablas.dart';
import 'producto_screen.dart';

/// Cada entrada o salida de stock con fecha, motivo y quién la hizo (pantalla
/// propia, para ver los de un producto).
class MovimientosScreen extends StatelessWidget {
  const MovimientosScreen({super.key, this.productoId});
  final String? productoId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Movimientos de stock')),
        body: MovimientosPanel(productoId: productoId),
      );
}

/// Movimientos en tabla, con filtro por tipo (pestaña del inventario).
class MovimientosPanel extends StatefulWidget {
  const MovimientosPanel({super.key, this.productoId});
  final String? productoId;

  @override
  State<MovimientosPanel> createState() => _MovimientosPanelState();
}

class _MovimientosPanelState extends State<MovimientosPanel> {
  TipoMovimiento? _tipo;
  String _q = '';

  @override
  Widget build(BuildContext context) => ReloadingFuture<List<Movimiento>>(
        contexto: 'movimientos',
        load: () => context.read<InventarioRepository>().movimientos(productoId: widget.productoId),
        builder: (context, todos, reload) {
          final q = _q.trim().toLowerCase();
          final lista = todos
              .where((m) => (_tipo == null || m.tipo == _tipo) && (q.isEmpty || m.productoNombre.toLowerCase().contains(q)))
              .toList();
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (widget.productoId == null) ...[
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar producto'),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: const Text('Todos'), selected: _tipo == null, onSelected: (_) => setState(() => _tipo = null)),
                    ),
                    for (final t in TipoMovimiento.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(label: Text(t.texto), selected: _tipo == t, onSelected: (v) => setState(() => _tipo = v ? t : null)),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                if (lista.isEmpty)
                  const EmptyState(icon: Icons.swap_vert, title: 'No hay movimientos', message: 'Las compras, ventas, ajustes y pérdidas aparecen acá.')
                else
                  TablaMovimientos(movimientos: lista),
              ],
            ),
          );
        },
      );
}

/// Colores por tipo de movimiento.
(Color, Color) _colorTipo(TipoMovimiento t) => switch (t) {
      TipoMovimiento.venta => (AppColors.blue, AppColors.blueSoft),
      TipoMovimiento.compra || TipoMovimiento.sobrantePedido || TipoMovimiento.anulacion => (AppColors.green, AppColors.greenSoft),
      TipoMovimiento.ajuste => (AppColors.orange, AppColors.orangeSoft),
      _ => (AppColors.red, AppColors.redSoft),
    };

/// Tabla de movimientos: Producto, Fecha, Cantidad, Tipo, Costo, Stock que
/// quedó, Valor, Referencia, Motivo y quién lo hizo.
class TablaMovimientos extends StatelessWidget {
  const TablaMovimientos({super.key, required this.movimientos});
  final List<Movimiento> movimientos;

  @override
  Widget build(BuildContext context) => tablaDeslizable(
        DataTable(
          headingRowColor: fondoEncabezadoTabla,
          headingTextStyle: estiloEncabezadoTabla,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          columnSpacing: 26,
          columns: const [
            DataColumn(label: Text('Producto')),
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Cantidad'), numeric: true),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Costo'), numeric: true),
            DataColumn(label: Text('Stock'), numeric: true),
            DataColumn(label: Text('Valor'), numeric: true),
            DataColumn(label: Text('Referencia')),
            DataColumn(label: Text('Motivo')),
            DataColumn(label: Text('Quién')),
          ],
          rows: [
            for (final m in movimientos)
              () {
                final (color, fondo) = _colorTipo(m.tipo);
                final entra = m.cantidad > 0;
                return DataRow(cells: [
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(m.productoNombre, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductoScreen(id: m.productoId))),
                  ),
                  DataCell(Text('${fechaTabla(m.fecha)} ${hora.format(m.fecha)}')),
                  DataCell(Text(
                    '${entra ? '+' : '−'}${cantidad(m.cantidad.abs())}',
                    style: estiloNumerosTabla.copyWith(fontWeight: FontWeight.w800, color: entra ? AppColors.green : AppColors.red),
                  )),
                  DataCell(EtiquetaEstado(m.tipo.texto, color, fondo)),
                  DataCell(Text(m.costoUnitario > 0 ? gs(m.costoUnitario) : '—', style: estiloNumerosTabla)),
                  DataCell(Text(cantidad(m.stockResultante), style: estiloNumerosTabla)),
                  DataCell(Text(m.valor > 0 ? gs(m.valor) : '—', style: estiloNumerosTabla)),
                  DataCell(Text(m.referencia ?? '—')),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(m.motivo ?? '—', overflow: TextOverflow.ellipsis),
                  )),
                  DataCell(Text(m.usuarioNombre ?? '—')),
                ]);
              }(),
          ],
        ),
      );
}
