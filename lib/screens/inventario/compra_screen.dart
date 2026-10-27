import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/compra.dart';
import '../../models/linea.dart';
import '../../models/producto.dart';
import '../../models/proveedor.dart';
import '../../providers/auth_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/inventario_repository.dart';
import '../../repositories/producto_repository.dart';
import '../../repositories/proveedor_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import '../../widgets/linea_editor.dart';
import 'producto_form.dart';

/// Compra propia para tener mercadería en stock (no es de un pedido).
class CompraScreen extends StatefulWidget {
  const CompraScreen({super.key, this.productoInicial});

  /// "Cargar compra" desde el inventario: arranca pidiendo la cantidad y el
  /// precio de compra de este producto.
  final Producto? productoInicial;

  @override
  State<CompraScreen> createState() => _CompraScreenState();
}

class _CompraScreenState extends State<CompraScreen> {
  List<Producto> _productos = const [];
  List<Proveedor> _proveedores = const [];
  String? _proveedorId;
  final _factura = TextEditingController();
  final List<LineaCompra> _lineas = [];
  bool _guardando = false;

  /// La misma en cada reintento: si se corta la señal, el stock no entra dos veces.
  final _clave = ClaveOperacion();

  @override
  void initState() {
    super.initState();
    _cargar().then((_) {
      final p = widget.productoInicial;
      if (p != null && mounted) _agregarProducto(p);
    });
  }

  Future<void> _cargar() async {
    final prods = context.read<ProductoRepository>();
    final provs = context.read<ProveedorRepository>();
    final p = await prods.listar();
    final v = await provs.listar();
    if (mounted) {
      setState(() {
        _productos = p;
        _proveedores = v;
        _proveedorId ??= v.firstOrNull?.id;
      });
    }
  }

  @override
  void dispose() {
    _factura.dispose();
    super.dispose();
  }

  Future<void> _agregar() async {
    // Se elige el producto con el mismo buscador de los pedidos y se pide el costo.
    final l = await agregarLinea(context, productos: _productos, esAdmin: context.read<AuthProvider>().esAdmin);
    if (l == null || !mounted) return;
    final prod = _productos.where((p) => p.id == l.productoId).firstOrNull;
    if (prod == null) {
      showSnack(context, 'Primero cargá "${l.descripcion}" como producto.', error: true);
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductoForm()));
      await _cargar();
      return;
    }
    if (!mounted) return;
    await _sumar(prod, l);
  }

  Future<void> _agregarProducto(Producto p) async {
    final l = await editarLinea(context, producto: p, esAdmin: true);
    if (l == null || !mounted) return;
    await _sumar(p, l);
  }

  /// Siempre se pregunta el precio de compra (trae el último: se cambia si subió o bajó).
  /// Si se compra por docena o caja, el stock entra en unidades y el costo
  /// se guarda por unidad.
  Future<void> _sumar(Producto prod, Linea l) async {
    final costo = await _pedirCosto(prod, l.unidad, l.factor);
    if (costo == null) return;
    setState(() => _lineas.add(LineaCompra(
          productoId: prod.id,
          descripcion: prod.nombre,
          unidad: prod.unidad,
          cantidad: l.cantidad * l.factor,
          costo: (costo / l.factor).round(),
        )));
  }

  Future<int?> _pedirCosto(Producto p, String forma, double factor) async {
    final ctrl = TextEditingController(text: p.precioCompra > 0 ? miles((p.precioCompra * factor).round()) : '');
    final form = GlobalKey<FormState>();
    final r = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Precio de compra de ${p.nombre}'),
        content: Form(
          key: form,
          child: MontoField(controller: ctrl, label: 'Precio de compra por $forma *', autofocus: true, validator: validarMonto(campo: 'el precio')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => form.currentState!.validate() ? Navigator.pop(c, leerMonto(ctrl.text)) : null, child: const Text('Listo')),
        ],
      ),
    );
    ctrl.dispose();
    return r;
  }

  Future<void> _guardar() async {
    if (_lineas.isEmpty) return showSnack(context, 'Agregá al menos un producto.', error: true);
    setState(() => _guardando = true);
    try {
      await context.read<InventarioRepository>().comprar(
            proveedorId: _proveedorId,
            factura: _factura.text,
            lineas: _lineas,
            clave: _clave.valor,
          );
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      showSnack(context, 'Compra registrada: el stock ya se actualizó');
      Navigator.pop(context);
    } catch (e) {
      registrarError('compra', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _lineas.fold<int>(0, (s, l) => s + l.total);
    return Scaffold(
      appBar: AppBar(title: const Text('Compra para stock')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 140),
        children: [
          Cuerpo(
            maxWidth: 720,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilaCampos(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _proveedorId,
                    decoration: const InputDecoration(labelText: 'Proveedor'),
                    items: [for (final p in _proveedores) DropdownMenuItem(value: p.id, child: Text(p.nombre))],
                    onChanged: (v) => setState(() => _proveedorId = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _factura,
                    inputFormatters: formatoTexto(Largo.factura),
                    decoration: const InputDecoration(labelText: 'Factura del proveedor (opcional)'),
                  ),
                ),
              ]),
              SectionTitle('Productos (${_lineas.length})', trailing: TextButton.icon(onPressed: _agregar, icon: const Icon(Icons.add), label: const Text('Agregar'))),
              if (_lineas.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('Agregá lo que compraste.', style: TextStyle(color: AppColors.muted))))
              else
                Card(
                  child: Column(children: [
                    for (var i = 0; i < _lineas.length; i++)
                      ListTile(
                        title: Text(_lineas[i].descripcion),
                        subtitle: Text('${cantidad(_lineas[i].cantidad)} × ${gs(_lineas[i].costo)}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(gs(_lineas[i].total), style: const TextStyle(fontWeight: FontWeight.w800)),
                          IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.red), onPressed: () => setState(() => _lineas.removeAt(i))),
                        ]),
                      ),
                  ]),
                ),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TotalDestacado(etiqueta: 'TOTAL DE LA COMPRA', monto: total),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: _guardando ? null : _guardar, icon: const Icon(Icons.check), label: Text(_guardando ? 'Guardando…' : 'Registrar compra')),
            ),
          ]),
        ),
      ),
    );
  }
}
