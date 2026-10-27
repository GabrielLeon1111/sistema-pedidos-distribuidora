import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/cliente.dart';
import '../../models/linea.dart';
import '../../models/producto.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/producto_repository.dart';
import '../../repositories/venta_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/cliente_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/linea_editor.dart';
import '../pedidos/entrega_screen.dart' show ModoPago;
import 'venta_screen.dart';

/// Venta directa desde el stock, sin pedido previo. Emite la factura.
class VentaDirectaScreen extends StatefulWidget {
  const VentaDirectaScreen({super.key});

  @override
  State<VentaDirectaScreen> createState() => _VentaDirectaScreenState();
}

class _VentaDirectaScreenState extends State<VentaDirectaScreen> {
  final _form = GlobalKey<FormState>();
  Cliente? _cliente;
  final List<Linea> _lineas = [];
  List<Producto> _productos = const [];
  ModoPago _modo = ModoPago.todo;
  String _metodo = 'efectivo';
  final _monto = TextEditingController();
  final _remision = TextEditingController();
  bool _guardando = false;

  /// La misma en cada reintento: si se corta la señal, no se vende (ni factura) dos veces.
  final _clave = ClaveOperacion();

  @override
  void initState() {
    super.initState();
    context.read<ProductoRepository>().listar().then((v) {
      if (mounted) setState(() => _productos = v);
    });
  }

  @override
  void dispose() {
    _monto.dispose();
    _remision.dispose();
    super.dispose();
  }

  int get _total => sumaTotales(_lineas);
  int get _pago => switch (_modo) {
        ModoPago.todo => _total,
        ModoPago.parte => leerMonto(_monto.text) ?? 0,
        ModoPago.fiado => 0,
      };

  Future<void> _vender() async {
    if (_cliente == null) return showSnack(context, 'Elegí el local.', error: true);
    if (_lineas.isEmpty) return showSnack(context, 'Agregá al menos un producto.', error: true);
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final v = await context.read<VentaRepository>().ventaDirecta(
            clienteId: _cliente!.id,
            lineas: _lineas,
            pago: PagoAlEntregar(monto: _pago, metodo: _metodo),
            notaRemision: _remision.text,
            clave: _clave.valor,
          );
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VentaScreen(id: v.id)));
    } catch (e) {
      registrarError('ventaDirecta', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Venta directa')),
        body: Form(
          key: _form,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 140),
            children: [
              Cuerpo(
                maxWidth: 720,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(_cliente?.nombre ?? 'Elegí el local *'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final c = await elegirCliente(context);
                        if (c != null) setState(() => _cliente = c);
                      },
                    ),
                  ),
                  SectionTitle(
                    'Productos del stock (${_lineas.length})',
                    trailing: TextButton.icon(
                      onPressed: () async {
                        final l = await agregarLinea(context, productos: _productos, esAdmin: true, soloStock: true);
                        if (l != null) setState(() => _lineas.add(l));
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                    ),
                  ),
                  if (_lineas.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('Agregá productos que tengas en stock.', style: TextStyle(color: AppColors.muted))))
                  else
                    Card(
                      child: Column(children: [
                        for (var i = 0; i < _lineas.length; i++)
                          ListTile(
                            title: Text(_lineas[i].descripcion),
                            subtitle: Text(['${cantidad(_lineas[i].cantidad)} ${_lineas[i].unidadTexto()} × ${gs(_lineas[i].precio)}', ?_lineas[i].textoDescuento].join(' · ')),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(gs(_lineas[i].total), style: const TextStyle(fontWeight: FontWeight.w800)),
                              IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.red), onPressed: () => setState(() => _lineas.removeAt(i))),
                            ]),
                          ),
                      ]),
                    ),
                  const SectionTitle('Cobro'),
                  SegmentedButton<ModoPago>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ModoPago.todo, label: Text('Pagó todo')),
                      ButtonSegment(value: ModoPago.parte, label: Text('Una parte')),
                      ButtonSegment(value: ModoPago.fiado, label: Text('Fiado')),
                    ],
                    selected: {_modo},
                    onSelectionChanged: (v) => setState(() => _modo = v.first),
                  ),
                  if (_modo == ModoPago.parte) ...[
                    const SizedBox(height: 12),
                    MontoField(controller: _monto, label: 'Cuánto pagó *', validator: validarMonto(campo: 'el monto', max: _total < 1 ? 1 : _total)),
                  ],
                  if (_modo != ModoPago.fiado) ...[
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'efectivo', label: Text('Efectivo')),
                        ButtonSegment(value: 'transferencia', label: Text('Transf.')),
                      ],
                      selected: {_metodo},
                      onSelectionChanged: (v) => setState(() => _metodo = v.first),
                    ),
                  ],
                  const SectionTitle('Factura'),
                  TextFormField(
                    controller: _remision,
                    inputFormatters: formatoTexto(30),
                    decoration: const InputDecoration(labelText: 'Nota de remisión N° (opcional)'),
                  ),
                ]),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TotalDestacado(etiqueta: 'TOTAL A PAGAR', monto: _total, detalle: _pago < _total ? 'Queda debiendo ${gs(_total - _pago)} · Crédito' : 'Contado'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _vender,
                  icon: const Icon(Icons.receipt_long),
                  label: Text(_guardando ? 'Guardando…' : 'Vender y emitir factura'),
                ),
              ),
            ]),
          ),
        ),
      );
}
