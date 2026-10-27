import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/linea.dart';
import '../models/producto.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../utils/validacion.dart';
import 'common.dart';

/// Buscar un producto por código o por las primeras letras y armar la línea.
/// Si no existe, se carga como nuevo (la app lo recuerda al guardar el pedido).
/// [soloStock]: venta directa: solo productos con stock.
Future<Linea?> agregarLinea(BuildContext context, {required List<Producto> productos, required bool esAdmin, bool soloStock = false}) async {
  final elegido = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _Buscador(productos: productos, soloStock: soloStock),
  );
  if (elegido == null || !context.mounted) return null;
  if (elegido is Producto) return editarLinea(context, producto: elegido, esAdmin: esAdmin, soloStock: soloStock);
  return editarLinea(context, nombreNuevo: elegido as String, esAdmin: esAdmin);
}

class _Buscador extends StatefulWidget {
  const _Buscador({required this.productos, required this.soloStock});
  final List<Producto> productos;
  final bool soloStock;

  @override
  State<_Buscador> createState() => _BuscadorState();
}

class _BuscadorState extends State<_Buscador> {
  String _q = '';

  /// Categoría elegida (null = todas).
  String? _categoria;

  @override
  Widget build(BuildContext context) {
    final base = widget.soloStock ? widget.productos.where((p) => p.stock > 0) : widget.productos;
    final categorias = {for (final p in base) ?p.categoria}.toList()..sort();
    final q = _q.trim().toLowerCase();
    // Primero los que coinciden con el código exacto, después por nombre.
    final lista = base.where((p) => p.coincide(_q) && (_categoria == null || p.categoria == _categoria)).toList()
      ..sort((a, b) {
        final ca = a.codigo?.toLowerCase() == q ? 0 : 1;
        final cb = b.codigo?.toLowerCase() == q ? 0 : 1;
        return ca != cb ? ca - cb : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    final exacto = base.any((p) => p.nombre.toLowerCase() == q);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.soloStock ? 'Producto del stock' : 'Agregar producto', style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Código o primeras letras'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            if (categorias.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  children: [
                    for (final c in [null, ...categorias])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c ?? 'Todas'),
                          selected: _categoria == c,
                          onSelected: (_) => setState(() => _categoria = c),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (!widget.soloStock && q.length >= 2 && !exacto)
              ListTile(
                leading: const CircleAvatar(backgroundColor: AppColors.accentSoft, child: Icon(Icons.add, color: AppColors.ink)),
                title: Text('Agregar "${_q.trim()}"'),
                subtitle: const Text('Producto nuevo: la app lo recuerda para la próxima'),
                onTap: () => Navigator.pop(context, limpiarTexto(_q)),
              ),
            Expanded(
              child: lista.isEmpty
                  ? EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: widget.soloStock
                          ? 'No hay productos con stock'
                          : (q.isEmpty ? 'Escribí el producto' : 'No hay productos con "$_q"${_categoria == null ? '' : ' en $_categoria'}'),
                      message: widget.soloStock ? null : 'Si es nuevo, escribí el nombre y tocá "Agregar".',
                    )
                  : ListView.separated(
                      itemCount: lista.length,
                      separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                      itemBuilder: (_, i) {
                        final p = lista[i];
                        return ListTile(
                          title: Text(p.nombre),
                          subtitle: Text([
                            if (p.codigo != null) 'Cód. ${p.codigo}',
                            p.textoPrecios.isEmpty ? p.unidad : p.textoPrecios,
                          ].join(' · ')),
                          trailing: p.stock > 0 ? StockPill(stock: p.stock, minStock: p.stockMinimo, unit: p.unidad) : null,
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Editar una línea: cantidad, precio, descuento y si sale del stock.
Future<Linea?> editarLinea(
  BuildContext context, {
  Linea? linea,
  Producto? producto,
  String? nombreNuevo,
  required bool esAdmin,
  bool soloStock = false,
}) =>
    showModalBottomSheet<Linea>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LineaSheet(linea: linea, producto: producto, nombreNuevo: nombreNuevo, esAdmin: esAdmin, soloStock: soloStock),
    );

enum _TipoDesc { ninguno, porcentaje, monto }

class _LineaSheet extends StatefulWidget {
  const _LineaSheet({this.linea, this.producto, this.nombreNuevo, required this.esAdmin, required this.soloStock});
  final Linea? linea;
  final Producto? producto;
  final String? nombreNuevo;
  final bool esAdmin;
  final bool soloStock;

  @override
  State<_LineaSheet> createState() => _LineaSheetState();
}

class _LineaSheetState extends State<_LineaSheet> {
  final _form = GlobalKey<FormState>();
  late final bool _nuevo = widget.producto == null && widget.linea?.productoId == null;
  late final _nombre = TextEditingController(text: widget.linea?.descripcion ?? widget.nombreNuevo ?? '');
  late final _codigo = TextEditingController(text: widget.linea?.codigo ?? widget.producto?.codigo ?? '');
  late String _unidad = widget.linea?.unidad ?? widget.producto?.unidad ?? 'unidad';
  // Cuántas unidades del stock es cada una (12 si se vende la docena).
  late double _factor = widget.producto?.forma(_unidad).unidades ?? widget.linea?.factor ?? 1;
  late final _cantidad = TextEditingController(text: widget.linea == null ? '' : cantidad(widget.linea!.cantidad));
  late final _nota = TextEditingController(text: widget.linea?.nota ?? '');
  late final _precio = TextEditingController(
      text: () {
        final v = widget.linea?.precio ?? widget.producto?.forma(_unidad).precio ?? 0;
        return v > 0 ? miles(v) : '';
      }());
  late _TipoDesc _tipoDesc = widget.linea?.descPct != null
      ? _TipoDesc.porcentaje
      : (widget.linea?.descMonto ?? 0) > 0
          ? _TipoDesc.monto
          : _TipoDesc.ninguno;
  late final _desc = TextEditingController(
      text: widget.linea?.descPct != null
          ? cantidad(widget.linea!.descPct!)
          : (widget.linea?.descMonto ?? 0) > 0
              ? miles(widget.linea!.descMonto)
              : '');
  late bool _deStock = widget.soloStock || (widget.linea?.deStock ?? false);

  @override
  void dispose() {
    for (final c in [_nombre, _codigo, _cantidad, _precio, _desc, _nota]) {
      c.dispose();
    }
    super.dispose();
  }

  Linea _armar() {
    final pct = _tipoDesc == _TipoDesc.porcentaje ? leerCantidad(_desc.text) : null;
    final monto = _tipoDesc == _TipoDesc.monto ? (leerMonto(_desc.text) ?? 0) : 0;
    return Linea(
      id: widget.linea?.id ?? const Uuid().v4(),
      productoId: widget.producto?.id ?? widget.linea?.productoId,
      codigo: limpiarTexto(_codigo.text).isEmpty ? null : limpiarTexto(_codigo.text),
      descripcion: widget.producto?.nombre ?? limpiarTexto(_nombre.text),
      unidad: _unidad,
      factor: _factor,
      nota: limpiarTexto(_nota.text).isEmpty ? null : limpiarTexto(_nota.text),
      cantidad: leerCantidad(_cantidad.text) ?? 0,
      precio: leerMonto(_precio.text) ?? 0,
      descPct: (pct ?? 0) > 0 ? pct : null,
      descMonto: monto,
      deStock: _deStock,
    );
  }

  /// Cambia la forma de venta y trae su último precio.
  void _elegirForma(Presentacion f) => setState(() {
        _unidad = f.nombre;
        _factor = f.unidades;
        _precio.text = f.precio > 0 ? miles(f.precio) : '';
      });

  void _listo() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, _armar());
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    final l = _armar();
    final stock = p?.stock ?? 0;
    final faltaStock = p != null && l.cantidad * _factor > stock + 0.0001;
    final formas = p?.formasDeVenta ?? const <Presentacion>[];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Form(
            key: _form,
            onChanged: () => setState(() {}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_nuevo ? 'Producto nuevo' : (p?.nombre ?? widget.linea!.descripcion), style: Theme.of(context).textTheme.titleLarge),
                if (!_nuevo && (p?.codigo ?? widget.linea?.codigo) != null)
                  Text('Código ${p?.codigo ?? widget.linea?.codigo}', style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 14),
                if (_nuevo) ...[
                  TextFormField(
                    controller: _nombre,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: formatoTexto(Largo.descripcion),
                    decoration: const InputDecoration(labelText: 'Nombre del producto *'),
                    validator: validarTexto(campo: 'el nombre', obligatorio: true, max: Largo.descripcion),
                  ),
                  const SizedBox(height: 12),
                  FilaCampos(anchoMinimo: 360, children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codigo,
                        inputFormatters: formatoTexto(30),
                        decoration: const InputDecoration(labelText: 'Código (opcional)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: unidadesSugeridas.contains(_unidad) ? _unidad : 'unidad',
                        decoration: const InputDecoration(labelText: 'Unidad'),
                        items: [for (final u in unidadesSugeridas) DropdownMenuItem(value: u, child: Text(u))],
                        onChanged: (v) => setState(() => _unidad = v ?? 'unidad'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                ],
                if (formas.length > 1) ...[
                  const Text('Se vende por', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final f in formas)
                      ChoiceChip(
                        selected: f.nombre.toLowerCase() == _unidad.toLowerCase(),
                        onSelected: (_) => _elegirForma(f),
                        label: Text([
                          f.esUnidad ? f.nombre : '${f.nombre} (${cantidad(f.unidades)} ${unidadPlural(p!.unidad, f.unidades)})',
                          if (f.precio > 0) gs(f.precio),
                        ].join(' · ')),
                      ),
                  ]),
                  const SizedBox(height: 12),
                ],
                FilaCampos(anchoMinimo: 360, children: [
                  Expanded(
                    child: CantidadField(
                      controller: _cantidad,
                      autofocus: !_nuevo,
                      suffix: textoForma(_unidad, _factor, 2),
                      ayuda: _deStock && stock > 0 ? 'En stock: ${cantidad(stock)} ${unidadPlural(p!.unidad, stock)}' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MontoField(
                      controller: _precio,
                      label: _factor > 1 ? 'Precio por $_unidad *' : 'Precio unitario *',
                      validator: validarMonto(campo: 'el precio', min: 0),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nota,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(150),
                  decoration: const InputDecoration(
                    labelText: 'Detalle (opcional)',
                    hintText: 'Ej: 1 rubio, 2 negros · talles · colores',
                    helperText: 'Sale en la nota de pedido y en la hoja del proveedor',
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Descuento', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                SegmentedButton<_TipoDesc>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _TipoDesc.ninguno, label: Text('Sin')),
                    ButtonSegment(value: _TipoDesc.porcentaje, label: Text('%')),
                    ButtonSegment(value: _TipoDesc.monto, label: Text('Gs.')),
                  ],
                  selected: {_tipoDesc},
                  onSelectionChanged: (v) => setState(() {
                    _tipoDesc = v.first;
                    _desc.clear();
                  }),
                ),
                if (_tipoDesc == _TipoDesc.porcentaje) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _desc,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Descuento', suffixText: '%', hintText: 'Ej: 10'),
                    validator: (v) {
                      final x = leerCantidad(v ?? '');
                      if (x == null || x <= 0 || x > 100) return 'Entre 0 y 100';
                      return null;
                    },
                  ),
                ],
                if (_tipoDesc == _TipoDesc.monto) ...[
                  const SizedBox(height: 10),
                  MontoField(controller: _desc, label: 'Descuento', validator: validarMonto(campo: 'el descuento')),
                ],
                if (!widget.soloStock && stock > 0) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: AppColors.accentSoft,
                    child: SwitchListTile(
                      value: _deStock,
                      onChanged: (v) => setState(() => _deStock = v),
                      title: Text('Tenés ${cantidad(stock)} ${unidadPlural(p!.unidad, stock)} en stock'),
                      subtitle: const Text('Usarlo antes de pedirlo al proveedor (no va en la hoja del proveedor)'),
                    ),
                  ),
                ],
                if (_deStock && faltaStock) ...[
                  const SizedBox(height: 8),
                  Aviso('Solo hay ${cantidad(stock)} ${unidadPlural(p.unidad, stock)} en stock'
                      '${_factor > 1 ? ' (pedís ${cantidad(l.cantidad * _factor)})' : ''}.',
                      icon: Icons.warning_amber_rounded, color: AppColors.red, fondo: AppColors.redSoft),
                ],
                const SizedBox(height: 14),
                TotalDestacado(etiqueta: 'TOTAL DE LA LÍNEA', monto: l.cantidad > 0 ? l.total : 0, detalle: l.textoDescuento),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: (_deStock && faltaStock && widget.soloStock) ? null : _listo,
                  icon: const Icon(Icons.check),
                  label: Text(widget.linea == null ? 'Agregar' : 'Listo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
