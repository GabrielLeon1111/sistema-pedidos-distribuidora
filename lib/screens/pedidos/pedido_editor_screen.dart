import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/cliente.dart';
import '../../models/linea.dart';
import '../../models/pedido.dart';
import '../../models/producto.dart';
import '../../providers/auth_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../providers/sincronizacion_provider.dart';
import '../../repositories/cliente_repository.dart';
import '../../repositories/pedido_repository.dart';
import '../../repositories/producto_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/cliente_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/linea_editor.dart';
import '../clientes/cliente_form.dart';
import 'pedido_detalle_screen.dart';

/// Nota de pedido nueva o editada (solo mientras no se pidió al proveedor).
class PedidoEditorScreen extends StatefulWidget {
  const PedidoEditorScreen({super.key, this.pedido});
  final Pedido? pedido;

  @override
  State<PedidoEditorScreen> createState() => _PedidoEditorScreenState();
}

class _PedidoEditorScreenState extends State<PedidoEditorScreen> {
  String? _clienteId;
  String? _clienteNombre;
  List<Rechazo> _rechazos = const [];
  late final List<Linea> _lineas = [...?widget.pedido?.lineas];
  late final _obs = TextEditingController(text: widget.pedido?.observaciones);
  late DateTime? _entrega = widget.pedido?.fechaEntrega;
  List<Producto> _productos = const [];
  bool _guardando = false;

  /// La misma en cada reintento: si se corta la señal, la nota no se guarda dos veces.
  final _clave = ClaveOperacion();

  @override
  void initState() {
    super.initState();
    final p = widget.pedido;
    if (p != null) {
      _clienteId = p.clienteId;
      _clienteNombre = p.cliente.nombre;
      _cargarRechazos();
    }
    context.read<ProductoRepository>().listar().then((v) {
      if (mounted) setState(() => _productos = v);
    });
  }

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  Future<void> _cargarRechazos() async {
    final id = _clienteId;
    if (id == null) return;
    try {
      final r = await context.read<ClienteRepository>().rechazos(id);
      if (mounted) setState(() => _rechazos = r);
    } catch (e) {
      registrarError('rechazos', e);
    }
  }

  Future<void> _elegirCliente() async {
    final Cliente? c = await elegirCliente(context);
    if (c == null) return;
    setState(() {
      _clienteId = c.id;
      _clienteNombre = c.nombre;
      _rechazos = const [];
    });
    _cargarRechazos();
  }

  /// Completar o corregir los datos del local elegido.
  Future<void> _editarCliente() async {
    final id = _clienteId;
    if (id == null) return;
    try {
      final actual = await context.read<ClienteRepository>().obtener(id);
      if (actual == null || !mounted) return;
      final c = await editarCliente(context, actual);
      if (c != null && mounted) setState(() => _clienteNombre = c.nombre);
    } catch (e) {
      registrarError('editarCliente', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    }
  }

  Producto? _producto(String? id) => id == null ? null : _productos.where((p) => p.id == id).firstOrNull;

  Future<void> _agregar() async {
    final esAdmin = context.read<AuthProvider>().esAdmin;
    final l = await agregarLinea(context, productos: _productos, esAdmin: esAdmin);
    if (l != null) setState(() => _lineas.add(l));
  }

  Future<void> _editar(int i) async {
    final esAdmin = context.read<AuthProvider>().esAdmin;
    final l = await editarLinea(context, linea: _lineas[i], producto: _producto(_lineas[i].productoId), esAdmin: esAdmin);
    if (l != null) setState(() => _lineas[i] = l);
  }

  Future<void> _guardar() async {
    if (_clienteId == null) return showSnack(context, 'Elegí el local.', error: true);
    if (_lineas.isEmpty) return showSnack(context, 'Agregá al menos un producto.', error: true);
    setState(() => _guardando = true);
    try {
      final p = await context.read<PedidoRepository>().guardar(
            id: widget.pedido?.id,
            clienteId: _clienteId!,
            lineas: _lineas,
            observaciones: _obs.text,
            fechaEntrega: _entrega,
            clave: _clave.valor,
          );
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      context.read<SincronizacionProvider>().recontar();
      showSnack(
        context,
        p.sinSincronizar
            ? 'Nota de pedido N° ${nroDoc(p.numero)} guardada en el teléfono: se sube sola cuando haya señal'
            : 'Nota de pedido N° ${nroDoc(p.numero)} guardada',
      );
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PedidoDetalleScreen(id: p.id)));
    } catch (e) {
      registrarError('guardarPedido', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = sumaTotales(_lineas);
    final rechazados = _rechazos.where((r) => r.detalle.startsWith('No recibió')).length;
    return PopScope(
      canPop: _lineas.isEmpty || widget.pedido != null,
      onPopInvokedWithResult: (pop, _) async {
        if (pop) return;
        final salir = await confirmar(context, titulo: '¿Salir sin guardar?', mensaje: 'Se pierde lo que cargaste en esta nota.', si: 'Salir', peligro: true);
        if (salir && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.pedido == null ? 'Nueva nota de pedido' : 'Editar pedido N° ${nroDoc(widget.pedido!.numero)}')),
        body: ListView(
          padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 120),
          children: [
            Cuerpo(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(_clienteNombre ?? 'Elegí el local *'),
                    subtitle: _clienteNombre == null ? const Text('Tocá para buscarlo o cargarlo') : null,
                    trailing: _clienteId == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(tooltip: 'Editar datos del local', icon: const Icon(Icons.edit_outlined), onPressed: _editarCliente),
                    onTap: _elegirCliente,
                  ),
                ),
                if (_rechazos.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Aviso(
                    rechazados > 0
                        ? 'Ojo: este local no recibió $rechazados ${rechazados == 1 ? 'pedido' : 'pedidos'} antes '
                            '(último: ${fechaCorta.format(_rechazos.first.fecha)}, ${_rechazos.first.detalle.toLowerCase()}).'
                        : 'Ojo: este local tiene ${_rechazos.length} rechazos o entregas parciales antes.',
                    icon: Icons.history_toggle_off,
                    color: AppColors.red,
                    fondo: AppColors.redSoft,
                  ),
                ],
                SectionTitle('Productos (${_lineas.length})',
                    trailing: TextButton.icon(onPressed: _agregar, icon: const Icon(Icons.add), label: const Text('Agregar'))),
                if (_lineas.isEmpty)
                  Card(
                    child: InkWell(
                      onTap: _agregar,
                      child: const Padding(
                        padding: EdgeInsets.all(22),
                        child: Column(children: [
                          Icon(Icons.add_shopping_cart, size: 36, color: AppColors.muted),
                          SizedBox(height: 8),
                          Text('Tocá para agregar el primer producto', style: TextStyle(color: AppColors.muted)),
                        ]),
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(children: [
                      for (var i = 0; i < _lineas.length; i++) ...[
                        if (i > 0) const Divider(),
                        _FilaLinea(
                          l: _lineas[i],
                          onTap: () => _editar(i),
                          onQuitar: () => setState(() => _lineas.removeAt(i)),
                        ),
                      ],
                    ]),
                  ),
                const SectionTitle('Más datos'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: Text(_entrega == null ? 'Fecha de entrega (opcional)' : 'Entrega: ${fechaCorta.format(_entrega!)}'),
                    trailing: _entrega == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _entrega = null)),
                    onTap: () async {
                      final f = await elegirFecha(context, inicial: _entrega ?? DateTime.now().add(const Duration(days: 1)), primera: DateTime.now());
                      if (f != null) setState(() => _entrega = f);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _obs,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(Largo.notas),
                  decoration: const InputDecoration(labelText: 'Observaciones', hintText: 'Ej: entregar antes de las 10'),
                ),
              ]),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TotalDestacado(etiqueta: 'TOTAL DEL PEDIDO', monto: total),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_guardando ? 'Guardando…' : 'Guardar nota de pedido'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FilaLinea extends StatelessWidget {
  const _FilaLinea({required this.l, required this.onTap, required this.onQuitar});
  final Linea l;
  final VoidCallback onTap;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.only(left: 14, right: 4),
        title: Text(l.descripcion, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          '${cantidad(l.cantidad)} ${l.unidadTexto()} × ${gs(l.precio)}',
          ?l.textoDescuento,
          if (l.deStock) 'Del stock',
          if (l.productoId == null) 'Nuevo',
        ].join(' · ') + (l.nota == null ? '' : '\nDetalle: ${l.nota}')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(gs(l.total), style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(tooltip: 'Quitar', icon: const Icon(Icons.delete_outline, color: AppColors.red), onPressed: onQuitar),
        ]),
      );
}
