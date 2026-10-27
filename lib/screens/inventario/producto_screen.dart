import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/movimiento.dart';
import '../../models/producto.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/inventario_repository.dart';
import '../../repositories/producto_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import 'movimientos_screen.dart';
import 'producto_form.dart';

/// Ficha del producto: precios, margen, stock y movimientos; ajustes, pérdidas y devoluciones.
class ProductoScreen extends StatelessWidget {
  const ProductoScreen({super.key, required this.id});
  final String id;

  Future<(Producto, List<Movimiento>)> _cargar(BuildContext context) async {
    final productos = context.read<ProductoRepository>();
    final inventario = context.read<InventarioRepository>();
    final p = await productos.obtener(id);
    if (p == null) throw StateError('producto');
    return (p, (await inventario.movimientos(productoId: id)).take(30).toList());
  }

  Future<void> _movimiento(BuildContext context, Producto p, String tipo) => movimientoDeStock(context, p, tipo);

  @override
  Widget build(BuildContext context) => ReloadingFuture<(Producto, List<Movimiento>)>(
        titulo: 'Producto',
        contexto: 'producto',
        load: () => _cargar(context),
        builder: (context, d, reload) {
          final (p, movs) = d;
          return Scaffold(
            appBar: AppBar(
              title: Text(p.nombre),
              actions: [
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductoForm(producto: p))),
                ),
              ],
            ),
            body: ListView(
              padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 32),
              children: [
                Cuerpo(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    GrillaTarjetas(children: [
                      StatCard(label: 'Stock', value: '${cantidad(p.stock)} ${unidadPlural(p.unidad, p.stock)}', detail: p.estadoStock.texto, icon: Icons.inventory_2_outlined),
                      StatCard(label: 'Valor en stock', value: gs(p.valorStock), icon: Icons.attach_money),
                      StatCard(label: 'Precio de venta', value: gs(p.precioVenta), detail: 'Por ${p.unidad} · ${ivaTexto(p.iva)}', icon: Icons.sell_outlined),
                      StatCard(
                        label: 'Margen',
                        value: p.margenPorcentaje == null ? '—' : '${p.margenPorcentaje!.toStringAsFixed(1)} %',
                        detail: p.precioCompra > 0 ? '${gs(p.gananciaUnidad)} por ${p.unidad}' : 'Sin precio de compra',
                        icon: Icons.trending_up,
                        highlight: true,
                      ),
                    ]),
                    if (p.presentaciones.isNotEmpty) ...[
                      const SectionTitle('Otras formas de venta'),
                      Card(
                        child: Column(children: [
                          for (final f in p.presentaciones)
                            ListTile(
                              dense: true,
                              title: Text('${f.nombre} de ${cantidad(f.unidades)} ${unidadPlural(p.unidad, f.unidades)}'),
                              subtitle: Text([
                                if (f.precio > 0) 'Sale ${gs((f.precio / f.unidades).round())} cada ${p.unidad}',
                                // El margen solo lo ve el administrador (esta pantalla es de Inventario).
                                if (f.precio > 0 && p.costoReferencia > 0) 'margen ${margenTexto(f.precio, (p.costoReferencia * f.unidades).round())}',
                                '${cantidad(p.stock / f.unidades)} en stock',
                              ].join(' · ')),
                              trailing: Text(f.precio > 0 ? gs(f.precio) : 'Sin precio', style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(children: [
                          KeyValueRow('Código', p.codigo ?? '—'),
                          KeyValueRow('Categoría', p.categoria ?? '—'),
                          KeyValueRow('Marca', p.marca ?? '—'),
                          KeyValueRow('Último precio de compra', gs(p.precioCompra)),
                          KeyValueRow('Costo promedio del stock', gs(p.costoPromedio)),
                          KeyValueRow('Stock mínimo', cantidad(p.stockMinimo)),
                        ]),
                      ),
                    ),
                    const SectionTitle('Stock'),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(onPressed: () => _movimiento(context, p, 'ajuste'), icon: const Icon(Icons.tune), label: const Text('Ajustar')),
                      OutlinedButton.icon(onPressed: () => _movimiento(context, p, 'perdida'), icon: const Icon(Icons.broken_image_outlined), label: const Text('Averiados')),
                      OutlinedButton.icon(onPressed: () => _movimiento(context, p, 'devolucion'), icon: const Icon(Icons.undo), label: const Text('Devolver al proveedor')),
                    ]),
                    SectionTitle(
                      'Movimientos',
                      trailing: TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MovimientosScreen(productoId: p.id))),
                        child: const Text('Ver todos'),
                      ),
                    ),
                    if (movs.isEmpty)
                      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Todavía no hay movimientos.', style: TextStyle(color: AppColors.muted))))
                    else
                      TablaMovimientos(movimientos: movs),
                  ]),
                ),
              ],
            ),
          );
        },
      );
}

/// Ajuste por conteo ('ajuste'), pérdida o averiado ('perdida') o devolución
/// al proveedor ('devolucion'): pide cantidad y motivo y lo registra.
/// Devuelve true si se guardó.
Future<bool> movimientoDeStock(BuildContext context, Producto p, String tipo) async {
  final r = await showModalBottomSheet<(double, String)>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MovimientoSheet(p: p, tipo: tipo),
  );
  if (r == null || !context.mounted) return false;
  final inv = context.read<InventarioRepository>();
  final clave = nuevaClave();
  final ok = await runSafe(context, 'movimiento_$tipo', () {
    return switch (tipo) {
      'ajuste' => inv.ajustar(p.id, r.$1, r.$2, clave: clave),
      'perdida' => inv.perdida(p.id, r.$1, r.$2, clave: clave),
      _ => inv.devolver(p.id, r.$1, r.$2, clave: clave),
    };
  }, ok: 'Stock actualizado');
  if (ok && context.mounted) context.read<RefreshBus>().changed();
  return ok;
}

class _MovimientoSheet extends StatefulWidget {
  const _MovimientoSheet({required this.p, required this.tipo});
  final Producto p;
  final String tipo;

  @override
  State<_MovimientoSheet> createState() => _MovimientoSheetState();
}

class _MovimientoSheetState extends State<_MovimientoSheet> {
  final _form = GlobalKey<FormState>();
  late final _cant = TextEditingController(text: widget.tipo == 'ajuste' ? cantidad(widget.p.stock) : '');
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _cant.dispose();
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titulo = switch (widget.tipo) {
      'ajuste' => 'Ajustar stock (conteo)',
      'perdida' => 'Averiados o perdidos',
      _ => 'Devolver al proveedor',
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(titulo, style: Theme.of(context).textTheme.titleLarge),
            Text('${widget.p.nombre} · hay ${cantidad(widget.p.stock)}', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            CantidadField(
              controller: _cant,
              autofocus: true,
              label: widget.tipo == 'ajuste' ? 'Stock real contado' : 'Cantidad',
              allowZero: widget.tipo == 'ajuste',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _motivo,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: formatoTexto(Largo.motivo),
              decoration: InputDecoration(
                labelText: 'Motivo *',
                hintText: widget.tipo == 'perdida' ? 'Ej: vencido, roto' : 'Ej: conteo del mes',
              ),
              validator: validarTexto(campo: 'el motivo', obligatorio: true, min: 3, max: Largo.motivo),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                Navigator.pop(context, (leerCantidad(_cant.text) ?? 0, limpiarTexto(_motivo.text)));
              },
              child: const Text('Guardar'),
            ),
          ]),
        ),
      ),
    );
  }
}
