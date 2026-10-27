import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/producto.dart';
import '../../models/proveedor.dart';
import '../../providers/negocio_provider.dart';
import '../../repositories/producto_repository.dart';
import '../../repositories/proveedor_repository.dart';
import '../../services/pdf_lista_compras.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/doc_actions.dart';
import '../../widgets/reloading_future.dart';

/// Lista de compras: arranca con los productos agotados o en el mínimo y una
/// cantidad sugerida. Se puede cambiar cuánto pedir, sumar otros productos y
/// sacar un PDF o imagen agrupado por proveedor (con o sin precios).
class ListaComprasScreen extends StatelessWidget {
  const ListaComprasScreen({super.key});

  Future<(List<Producto>, List<Proveedor>)> _cargar(BuildContext context) async {
    final productos = context.read<ProductoRepository>();
    final proveedores = context.read<ProveedorRepository>();
    return (await productos.listar(), await proveedores.listar(incluirInactivos: true));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Lista de compras')),
        body: ReloadingFuture<(List<Producto>, List<Proveedor>)>(
          contexto: 'listaCompras',
          load: () => _cargar(context),
          builder: (context, d, reload) => _Panel(productos: d.$1, proveedores: {for (final p in d.$2) p.id: p.nombre}, onRefresh: reload),
        ),
      );
}

/// Hay que comprar: agotado o en el mínimo.
bool _hayQueComprar(Producto p) => p.stock <= 0 || (p.stockMinimo > 0 && p.stock <= p.stockMinimo);

/// Cuánto pedir de entrada: hasta el doble del mínimo (o 1 si no tiene mínimo).
double _sugerido(Producto p) {
  final s = (p.stockMinimo * 2 - p.stock).ceilToDouble();
  return s < 1 ? 1 : s;
}

class _Panel extends StatefulWidget {
  const _Panel({required this.productos, required this.proveedores, required this.onRefresh});
  final List<Producto> productos;
  final Map<String, String> proveedores;
  final Future<void> Function() onRefresh;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  /// Producto → cuánto pedir. Lo que no está acá no va en la lista.
  final Map<String, double> _pedido = {};
  bool _verTodos = false;
  bool _conPrecios = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    for (final p in widget.productos.where(_hayQueComprar)) {
      _pedido[p.id] = _sugerido(p);
    }
  }

  List<LineaCompraLista> get _lineas => [
        for (final p in widget.productos)
          if (_pedido.containsKey(p.id)) LineaCompraLista(p, _pedido[p.id]!, widget.proveedores[p.proveedorId] ?? ''),
      ];

  void _cambiar(Producto p, double cant) => setState(() {
        if (cant <= 0) {
          _pedido.remove(p.id);
        } else {
          _pedido[p.id] = cant > 100000 ? 100000 : cant;
        }
      });

  Future<void> _escribirCantidad(Producto p) async {
    final ctrl = TextEditingController(text: _pedido[p.id] == null ? '' : cantidad(_pedido[p.id]!).replaceAll('.', ''));
    final n = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(p.nombre),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          decoration: InputDecoration(labelText: '¿Cuánto pedir?', suffixText: unidadPlural(p.unidad, 2)),
          onSubmitted: (v) => Navigator.pop(c, double.tryParse(v) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text) ?? 0), child: const Text('Listo')),
        ],
      ),
    );
    ctrl.dispose();
    if (n != null) _cambiar(p, n);
  }

  @override
  Widget build(BuildContext context) {
    final negocio = context.watch<NegocioProvider>().negocio;
    final lineas = _lineas;
    final total = lineas.fold<int>(0, (s, l) => s + l.subtotal);
    final paraComprar = widget.productos.where(_hayQueComprar).length;
    var visibles = _verTodos ? widget.productos : widget.productos.where((p) => _hayQueComprar(p) || _pedido.containsKey(p.id)).toList();
    if (_verTodos && _q.trim().isNotEmpty) visibles = visibles.where((p) => p.coincide(_q)).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('PARA COMPRAR', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Text('${lineas.length} ${lineas.length == 1 ? 'producto' : 'productos'}',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  Text('Total estimado: ${gs(total)}', style: const TextStyle(color: Colors.white70, fontSize: 15)),
                ]),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: Text('Agotados o en el mínimo ($paraComprar)'), selected: !_verTodos, onSelected: (_) => setState(() => _verTodos = false)),
                ChoiceChip(label: const Text('Todos los productos'), selected: _verTodos, onSelected: (_) => setState(() => _verTodos = true)),
              ]),
              if (_verTodos)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar producto', isDense: true),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
              const SizedBox(height: 10),
              if (visibles.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No hay productos agotados ni en el mínimo. Tocá "Todos los productos" para armar un pedido igual.',
                        style: TextStyle(color: AppColors.muted)),
                  ),
                )
              else
                Card(
                  child: Column(children: [
                    for (var k = 0; k < visibles.length; k++) ...[
                      if (k > 0) const Divider(height: 1, indent: 14, endIndent: 14),
                      _Fila(
                        p: visibles[k],
                        proveedor: widget.proveedores[visibles[k].proveedorId],
                        cantidad: _pedido[visibles[k].id],
                        onCambiar: (c) => _cambiar(visibles[k], c),
                        onEscribir: () => _escribirCantidad(visibles[k]),
                      ),
                    ],
                  ]),
                ),
              const SectionTitle('Generar la lista'),
              Card(
                child: SwitchListTile(
                  value: _conPrecios,
                  onChanged: (v) => setState(() => _conPrecios = v),
                  title: const Text('Incluir costos y total'),
                  subtitle: const Text('Desactivalo para mandársela al proveedor'),
                ),
              ),
              const SizedBox(height: 10),
              if (lineas.isEmpty)
                const Text('Agregá al menos un producto para generar la lista.', style: TextStyle(color: AppColors.muted))
              else
                DocActions(
                  // Si cambia el pedido, se genera de nuevo.
                  key: ValueKey(Object.hash(_conPrecios, Object.hashAll(lineas.map((l) => '${l.producto.id}:${l.cantidad}')))),
                  fileName: archivoListaCompras(DateTime.now()),
                  shareText: 'Hola! Te paso el pedido de ${negocio.nombre} (${lineas.length} productos). Por favor confirmame precios y disponibilidad. ¡Gracias!',
                  build: () => pdfListaCompras(lineas, negocio, conPrecios: _conPrecios),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.p, required this.proveedor, required this.cantidad, required this.onCambiar, required this.onEscribir});
  final Producto p;
  final String? proveedor;
  final double? cantidad;
  final ValueChanged<double> onCambiar;
  final VoidCallback onEscribir;

  @override
  Widget build(BuildContext context) {
    final incluido = cantidad != null;
    final detalle = [
      'Stock ${_cant(p.stock)}',
      if (p.stockMinimo > 0) 'mínimo ${_cant(p.stockMinimo)}',
      ?proveedor,
      if (p.costoReferencia > 0) gs(p.costoReferencia),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
      child: Row(children: [
        Checkbox(value: incluido, onChanged: (v) => onCambiar(v == true ? _sugerido(p) : 0)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (p.stock <= 0)
                const Pill('Agotado', color: AppColors.red, background: AppColors.redSoft)
              else if (p.stockMinimo > 0 && p.stock <= p.stockMinimo)
                const Pill('Bajo', color: AppColors.orange, background: AppColors.orangeSoft),
              Text(detalle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ]),
          ]),
        ),
        if (incluido) ...[
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Menos',
            onPressed: () => onCambiar(cantidad! - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          InkWell(
            onTap: onEscribir,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(minWidth: 46),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                Text(_cant(cantidad!), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(unidadPlural(p.unidad, cantidad!), style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
              ]),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Más',
            onPressed: () => onCambiar(cantidad! + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ]),
    );
  }
}

String _cant(double v) => cantidad(v);
