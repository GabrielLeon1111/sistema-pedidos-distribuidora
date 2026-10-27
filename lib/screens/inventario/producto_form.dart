import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/producto.dart';
import '../../models/proveedor.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/producto_repository.dart';
import '../../repositories/proveedor_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';

/// Alta o edición de un producto (precios, IVA, proveedor y stock mínimo).
class ProductoForm extends StatefulWidget {
  const ProductoForm({super.key, this.producto});
  final Producto? producto;

  @override
  State<ProductoForm> createState() => _ProductoFormState();
}

class _ProductoFormState extends State<ProductoForm> {
  final _form = GlobalKey<FormState>();
  late final p = widget.producto;
  late final _nombre = TextEditingController(text: p?.nombre);
  late final _codigo = TextEditingController(text: p?.codigo);
  late final _categoria = TextEditingController(text: p?.categoria);
  late final _marca = TextEditingController(text: p?.marca);
  late final _venta = TextEditingController(text: (p?.precioVenta ?? 0) > 0 ? miles(p!.precioVenta) : '');
  late final _compra = TextEditingController(text: (p?.precioCompra ?? 0) > 0 ? miles(p!.precioCompra) : '');
  late final _minimo = TextEditingController(text: (p?.stockMinimo ?? 0) > 0 ? cantidad(p!.stockMinimo) : '');
  late String _unidad = p?.unidad ?? 'unidad';
  late int _iva = p?.iva ?? 10;
  late String? _proveedorId = p?.proveedorId;
  late final List<_Forma> _formas = [for (final f in p?.presentaciones ?? const <Presentacion>[]) _Forma.de(f)];
  List<Proveedor> _proveedores = const [];
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    context.read<ProveedorRepository>().listar().then((v) {
      if (mounted) setState(() => _proveedores = v);
    });
  }

  @override
  void dispose() {
    for (final c in [_nombre, _codigo, _categoria, _marca, _venta, _compra, _minimo]) {
      c.dispose();
    }
    for (final f in _formas) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    String? t(TextEditingController c) => limpiarTexto(c.text).isEmpty ? null : limpiarTexto(c.text);
    try {
      await context.read<ProductoRepository>().guardar(Producto(
            id: p?.id ?? const Uuid().v4(),
            codigo: t(_codigo),
            nombre: limpiarTexto(_nombre.text),
            unidad: _unidad,
            categoria: t(_categoria),
            marca: t(_marca),
            proveedorId: _proveedorId,
            precioVenta: leerMonto(_venta.text) ?? 0,
            precioCompra: leerMonto(_compra.text) ?? 0,
            stockMinimo: leerCantidad(_minimo.text) ?? 0,
            iva: _iva,
            activo: p?.activo ?? true,
            creado: p?.creado ?? DateTime.now(),
            presentaciones: [for (final f in _formas) f.armar()],
          ));
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      Navigator.pop(context);
    } catch (e) {
      registrarError('guardarProducto', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _filaForma(int i, int costoUnidad) {
    final f = _formas[i];
    final u = leerCantidad(f.unidades.text) ?? 0;
    final pr = leerMonto(f.precio.text) ?? 0;
    final costo = (costoUnidad * u).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: f.nombre,
                decoration: const InputDecoration(labelText: 'Forma *'),
                items: [
                  for (final s in {...formasSugeridas, f.nombre})
                    if (s != _unidad) DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (s) => setState(() => f.nombre = s ?? f.nombre),
                validator: (x) => x == _unidad
                    ? 'Ya es la unidad'
                    : _formas.where((o) => o.nombre == x).length > 1
                        ? 'Repetida'
                        : null,
              ),
            ),
            IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.delete_outline, color: AppColors.red),
              onPressed: () => setState(() => _formas.removeAt(i).dispose()),
            ),
          ]),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilaCampos(children: [
              Expanded(
                child: TextFormField(
                  controller: f.unidades,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: '¿Cuántas ${unidadPlural(_unidad, 2)} trae? *'),
                  validator: (x) => (leerCantidad(x ?? '') ?? 0) > 1 ? null : 'Más de 1',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: MontoField(controller: f.precio, label: 'Precio de venta')),
            ]),
          ),
          if (u > 1 && pr > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Text(
                [
                  'Sale ${gs((pr / u).round())} cada ${_unidad == 'unidad' ? 'una' : _unidad}',
                  if (costo > 0) 'margen ${margenTexto(pr, costo)}',
                ].join(' · '),
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = leerMonto(_venta.text) ?? 0;
    final c = leerMonto(_compra.text) ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(p == null ? 'Nuevo producto' : 'Editar producto')),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: EdgeInsets.fromLTRB(margenLateral(context), 8, margenLateral(context), 100),
          children: [
            Cuerpo(
              maxWidth: 640,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(Largo.descripcion),
                  decoration: const InputDecoration(labelText: 'Nombre *'),
                  validator: validarTexto(campo: 'el nombre', obligatorio: true, max: Largo.descripcion),
                ),
                const SizedBox(height: 12),
                FilaCampos(children: [
                  Expanded(child: TextFormField(controller: _codigo, inputFormatters: formatoTexto(30), decoration: const InputDecoration(labelText: 'Código'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: unidadesSugeridas.contains(_unidad) ? _unidad : 'unidad',
                      decoration: const InputDecoration(labelText: 'Unidad'),
                      items: [for (final u in unidadesSugeridas) DropdownMenuItem(value: u, child: Text(u))],
                      onChanged: (x) => setState(() => _unidad = x ?? 'unidad'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                FilaCampos(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _categoria,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: formatoTexto(Largo.categoria),
                      decoration: const InputDecoration(labelText: 'Categoría', hintText: 'Ej: Cosméticos'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _marca,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: formatoTexto(Largo.marca),
                      decoration: const InputDecoration(labelText: 'Marca'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _proveedores.any((x) => x.id == _proveedorId) ? _proveedorId : null,
                  decoration: const InputDecoration(labelText: 'Proveedor'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('El principal')),
                    for (final x in _proveedores) DropdownMenuItem(value: x.id, child: Text(x.nombre)),
                  ],
                  onChanged: (x) => setState(() => _proveedorId = x),
                ),
                const SectionTitle('Precios'),
                FilaCampos(children: [
                  Expanded(child: MontoField(controller: _venta, label: 'Precio de venta por $_unidad')),
                  const SizedBox(width: 12),
                  Expanded(child: MontoField(controller: _compra, label: 'Último precio de compra por $_unidad')),
                ]),
                if (c > 0 && v > 0) ...[
                  const SizedBox(height: 8),
                  Aviso('Margen: ${margenTexto(v, c)}', icon: Icons.trending_up, color: AppColors.green, fondo: AppColors.greenSoft),
                ],
                SectionTitle(
                  'Otras formas de venta',
                  trailing: TextButton.icon(
                    onPressed: _formas.length >= 6 ? null : () => setState(() => _formas.add(_Forma.nueva(formasSugeridas.firstWhere((s) => s != _unidad && _formas.every((o) => o.nombre != s), orElse: () => 'pack')))),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar'),
                  ),
                ),
                if (_formas.isEmpty)
                  Text('Se vende solo por $_unidad. Si también se vende por docena, paquete o caja, tocá "Agregar".',
                      style: const TextStyle(color: AppColors.muted))
                else
                  for (var i = 0; i < _formas.length; i++) _filaForma(i, c),
                const SizedBox(height: 14),
                const Text('IVA (para la factura)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 10, label: Text('10 %')),
                    ButtonSegment(value: 5, label: Text('5 %')),
                    ButtonSegment(value: 0, label: Text('Exenta')),
                  ],
                  selected: {_iva},
                  onSelectionChanged: (x) => setState(() => _iva = x.first),
                ),
                const SectionTitle('Stock'),
                CantidadField(controller: _minimo, label: 'Stock mínimo (aviso de "por agotarse")', obligatorio: false, allowZero: true),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(onPressed: _guardando ? null : _guardar, icon: const Icon(Icons.check), label: Text(_guardando ? 'Guardando…' : 'Guardar')),
        ),
      ),
    );
  }
}

/// Los campos de una forma de venta mientras se edita.
class _Forma {
  _Forma(this.nombre, String unidades, String precio)
      : unidades = TextEditingController(text: unidades),
        precio = TextEditingController(text: precio);

  factory _Forma.de(Presentacion p) => _Forma(p.nombre, cantidad(p.unidades), p.precio > 0 ? miles(p.precio) : '');
  factory _Forma.nueva(String nombre) => _Forma(nombre, nombre == 'docena' ? '12' : '', '');

  String nombre;
  final TextEditingController unidades;
  final TextEditingController precio;

  Presentacion armar() => Presentacion(
        nombre: nombre,
        unidades: leerCantidad(unidades.text) ?? 0,
        precio: leerMonto(precio.text) ?? 0,
      );

  void dispose() {
    unidades.dispose();
    precio.dispose();
  }
}
