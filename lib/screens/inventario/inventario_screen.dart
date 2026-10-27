import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/producto.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/producto_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import '../../widgets/tablas.dart';
import 'compra_screen.dart';
import 'lista_compras_screen.dart';
import 'movimientos_screen.dart';
import 'producto_form.dart';
import 'producto_screen.dart';

enum _Filtro { todos, porAgotarse, agotados, inactivos }

/// Inventario en dos pestañas: Productos (tabla con stock, costo promedio,
/// precio de venta, valorizado y estado) y Movimientos.
class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  String _q = '';
  String? _categoria;
  _Filtro _filtro = _Filtro.todos;

  static bool _porAgotarse(Producto p) => p.activo && p.stock > 0 && p.stockMinimo > 0 && p.stock <= p.stockMinimo;
  static bool _agotado(Producto p) => p.activo && p.stock <= 0;

  @override
  Widget build(BuildContext context) => ReloadingFuture<List<Producto>>(
        titulo: 'Inventario',
        contexto: 'inventario',
        load: () => context.read<ProductoRepository>().listar(incluirInactivos: true),
        builder: (context, todos, reload) {
          final activos = todos.where((p) => p.activo).toList();
          final invertido = activos.fold<int>(0, (s, p) => s + p.valorStock);
          final porAgotarse = activos.where(_porAgotarse).length;
          final agotados = activos.where(_agotado).length;
          final categorias = {for (final p in activos) ?p.categoria}.toList()..sort();

          Iterable<Producto> lista = switch (_filtro) {
            _Filtro.todos => activos,
            _Filtro.porAgotarse => activos.where(_porAgotarse),
            _Filtro.agotados => activos.where(_agotado),
            _Filtro.inactivos => todos.where((p) => !p.activo),
          };
          if (_categoria != null) lista = lista.where((p) => p.categoria == _categoria);
          if (_q.trim().isNotEmpty) lista = lista.where((p) => p.coincide(_q));
          final items = lista.toList();
          final paraComprar = porAgotarse + agotados;

          return DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Inventario'),
                actions: [
                  TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ListaComprasScreen())),
                    icon: const Icon(Icons.add_shopping_cart_rounded),
                    label: Text(paraComprar > 0 ? 'Lista de compras ($paraComprar)' : 'Lista de compras'),
                  ),
                  const SizedBox(width: 6),
                ],
                bottom: const TabBar(
                  labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  tabs: [Tab(text: 'Productos'), Tab(text: 'Movimientos')],
                ),
              ),
              body: TabBarView(
                children: [
                  RefreshIndicator(
                    onRefresh: reload,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: _Invertido(invertido: invertido, activos: activos.length),
                          ),
                        ),
                        // ---------- Compras: la mercadería que entra ----------
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  const Row(children: [
                                    Icon(Icons.local_shipping_outlined, color: AppColors.ink),
                                    SizedBox(width: 8),
                                    Text('Compras', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  ]),
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2, bottom: 10),
                                    child: Text('Cargá la mercadería que comprás para tener en stock: se actualiza solo.',
                                        style: TextStyle(color: AppColors.muted, fontSize: 13)),
                                  ),
                                  Row(children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompraScreen())),
                                        icon: const Icon(Icons.add_rounded),
                                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Nueva compra')),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductoForm())),
                                        icon: const Icon(Icons.add_box_outlined),
                                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Nuevo producto')),
                                      ),
                                    ),
                                  ]),
                                ]),
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: TextField(
                              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar producto'),
                              onChanged: (v) => setState(() => _q = v),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 44,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              children: [
                                _chip('Todos', _Filtro.todos),
                                _chip('Por agotarse${porAgotarse > 0 ? ' ($porAgotarse)' : ''}', _Filtro.porAgotarse),
                                _chip('Agotados${agotados > 0 ? ' ($agotados)' : ''}', _Filtro.agotados),
                                _chip('Inactivos', _Filtro.inactivos),
                                if (categorias.isNotEmpty) ...[
                                  const VerticalDivider(width: 16, indent: 8, endIndent: 8),
                                  for (final c in categorias)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: FilterChip(
                                        label: Text(c),
                                        selected: _categoria == c,
                                        onSelected: (_) => setState(() => _categoria = _categoria == c ? null : c),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (items.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: EmptyState(
                              icon: Icons.inventory_2_outlined,
                              title: todos.isEmpty ? 'Todavía no hay productos' : 'No hay productos con ese filtro',
                              message: todos.isEmpty ? 'Se agregan solos al cargar pedidos, o con "Nuevo producto".' : null,
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            sliver: SliverToBoxAdapter(child: TablaProductos(productos: items)),
                          ),
                      ],
                    ),
                  ),
                  const MovimientosPanel(),
                ],
              ),
            ),
          );
        },
      );

  Widget _chip(String label, _Filtro f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: _filtro == f, onSelected: (_) => setState(() => _filtro = f)),
      );
}

class _Invertido extends StatelessWidget {
  const _Invertido({required this.invertido, required this.activos});
  final int invertido;
  final int activos;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('INVERTIDO EN MERCADERÍA',
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(gs(invertido), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26)),
          ),
          Text('$activos productos activos · a costo promedio', style: const TextStyle(color: Colors.white60, fontSize: 13)),
        ]),
      );
}

EtiquetaEstado _estado(Producto p) {
  if (!p.activo) return const EtiquetaEstado('Inactivo', AppColors.muted, AppColors.line);
  if (p.stock <= 0) return const EtiquetaEstado('Agotado', AppColors.red, AppColors.redSoft);
  if (p.stockMinimo > 0 && p.stock <= p.stockMinimo) return const EtiquetaEstado('Por agotarse', AppColors.orange, AppColors.orangeSoft);
  return const EtiquetaEstado('Disponible', AppColors.green, AppColors.greenSoft);
}

/// Tabla de productos: Producto, Marca, Categoría, Stock, Costo prom., Precio
/// venta, Ganancia (% y Gs. por unidad), Valorizado, Estado y Acciones. Con casillas para activar o
/// desactivar varios a la vez.
class TablaProductos extends StatefulWidget {
  const TablaProductos({super.key, required this.productos});
  final List<Producto> productos;

  @override
  State<TablaProductos> createState() => _TablaProductosState();
}

class _TablaProductosState extends State<TablaProductos> {
  final Set<String> _sel = {};

  void _refrescar() {
    if (mounted) context.read<RefreshBus>().changed();
  }

  void _abrir(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _refrescar());

  Future<void> _accion(String a, Producto p) async {
    switch (a) {
      case 'detalle':
        _abrir(ProductoScreen(id: p.id));
      case 'editar':
        _abrir(ProductoForm(producto: p));
      case 'compra':
        _abrir(CompraScreen(productoInicial: p));
      case 'ajustar':
        await movimientoDeStock(context, p, 'ajuste');
      case 'averiados':
        await movimientoDeStock(context, p, 'perdida');
      case 'devolver':
        await movimientoDeStock(context, p, 'devolucion');
      case 'activo':
        final ok = await runSafe(
          context,
          'activarProducto',
          () => context.read<ProductoRepository>().activar(p.id, !p.activo),
          ok: p.activo ? 'Producto desactivado: ya no aparece al cargar pedidos' : 'Producto activado',
        );
        if (ok) _refrescar();
    }
  }

  Future<void> _masivo(bool activar) async {
    final ids = _sel.toList();
    final ok = await confirmar(
      context,
      titulo: activar ? 'Activar productos' : 'Desactivar productos',
      mensaje: activar
          ? 'Se activan ${ids.length} productos: vuelven a aparecer al cargar pedidos.'
          : 'Se desactivan ${ids.length} productos: dejan de aparecer al cargar pedidos (no se borra nada).',
      si: activar ? 'Activar' : 'Desactivar',
    );
    if (!ok || !mounted) return;
    final repo = context.read<ProductoRepository>();
    final hecho = await runSafe(context, 'masivoProductos', () async {
      for (final id in ids) {
        await repo.activar(id, activar);
      }
    }, ok: activar ? 'Productos activados' : 'Productos desactivados');
    if (hecho) {
      setState(_sel.clear);
      _refrescar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = widget.productos;
    _sel.removeWhere((id) => !lista.any((p) => p.id == id));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_sel.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(child: Text('${_sel.length} seleccionados', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            TextButton(onPressed: () => _masivo(true), child: const Text('Activar', style: TextStyle(color: AppColors.accent))),
            TextButton(onPressed: () => _masivo(false), child: const Text('Desactivar', style: TextStyle(color: AppColors.accent))),
            IconButton(onPressed: () => setState(_sel.clear), icon: const Icon(Icons.close, color: Colors.white70)),
          ]),
        ),
      tablaDeslizable(
        DataTable(
          headingRowColor: fondoEncabezadoTabla,
          headingTextStyle: estiloEncabezadoTabla,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 64,
          columnSpacing: 28,
          showCheckboxColumn: true,
          columns: const [
            DataColumn(label: Text('Producto')),
            DataColumn(label: Text('Marca')),
            DataColumn(label: Text('Categoría')),
            DataColumn(label: Text('Stock'), numeric: true),
            DataColumn(label: Text('Costo prom.'), numeric: true),
            DataColumn(label: Text('Precio venta'), numeric: true),
            DataColumn(label: Text('Ganancia'), numeric: true),
            DataColumn(label: Text('Valorizado'), numeric: true),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: [
            for (final p in lista)
              DataRow(
                selected: _sel.contains(p.id),
                onSelectChanged: (v) => setState(() => v == true ? _sel.add(p.id) : _sel.remove(p.id)),
                cells: [
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                    onTap: () => _accion('detalle', p),
                  ),
                  DataCell(Text(p.marca ?? '—')),
                  DataCell(Text(p.categoria ?? '—')),
                  DataCell(Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(cantidad(p.stock), style: estiloNumerosTabla.copyWith(fontWeight: FontWeight.w800)),
                      Text(unidadPlural(p.unidad, p.stock), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    ],
                  )),
                  DataCell(Text(p.costoReferencia == 0 ? '—' : gs(p.costoReferencia), style: estiloNumerosTabla)),
                  DataCell(Text(p.precioVenta == 0 ? '—' : gs(p.precioVenta), style: estiloNumerosTabla)),
                  // Cuánto gana por unidad sobre lo que pagó: % y guaraníes.
                  DataCell(p.margenPorcentaje == null
                      ? const Text('—', style: estiloNumerosTabla)
                      : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${p.margenPorcentaje!.toStringAsFixed(1)} %',
                              style: estiloNumerosTabla.copyWith(fontWeight: FontWeight.w800, color: p.gananciaUnidad >= 0 ? AppColors.green : AppColors.red)),
                          Text(gs(p.gananciaUnidad), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                        ])),
                  DataCell(Text(gs(p.valorStock), style: estiloNumerosTabla)),
                  DataCell(_estado(p)),
                  DataCell(
                    PopupMenuButton<String>(
                      tooltip: 'Acciones',
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (a) => _accion(a, p),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'detalle', child: Text('Ver detalle')),
                        const PopupMenuItem(value: 'editar', child: Text('Editar')),
                        const PopupMenuItem(value: 'compra', child: Text('Cargar compra')),
                        const PopupMenuItem(value: 'ajustar', child: Text('Ajustar stock')),
                        const PopupMenuItem(value: 'averiados', child: Text('Averiados')),
                        const PopupMenuItem(value: 'devolver', child: Text('Devolver al proveedor')),
                        PopupMenuItem(value: 'activo', child: Text(p.activo ? 'Desactivar' : 'Activar')),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ]);
  }
}
