import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/linea.dart';
import '../../models/pedido.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/venta_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import '../ventas/venta_screen.dart';

enum ModoPago { todo, parte, fiado }

/// Entrega del pedido: qué recibió el local, cómo pagó, y se emite la factura.
class EntregaScreen extends StatefulWidget {
  const EntregaScreen({super.key, required this.pedido, this.sena = 0});
  final Pedido pedido;
  final int sena;

  @override
  State<EntregaScreen> createState() => _EntregaScreenState();
}

class _EntregaScreenState extends State<EntregaScreen> {
  final _form = GlobalKey<FormState>();
  bool _parcial = false;
  late final Map<String, TextEditingController> _cant = {
    for (final l in widget.pedido.lineas)
      if (l.cantidadEfectiva > 0) l.id: TextEditingController(text: cantidad(l.cantidadEfectiva)),
  };
  ModoPago _modo = ModoPago.todo;
  final _monto = TextEditingController();
  final _remision = TextEditingController();
  String _metodo = 'efectivo';
  bool _guardando = false;

  /// La misma en cada reintento: si se corta la señal, no se entrega (ni factura) dos veces.
  final _clave = ClaveOperacion();

  List<Linea> get _lineas => widget.pedido.lineas.where((l) => l.cantidadEfectiva > 0).toList();

  @override
  void dispose() {
    for (final c in _cant.values) {
      c.dispose();
    }
    _monto.dispose();
    _remision.dispose();
    super.dispose();
  }

  double _recibido(Linea l) => _parcial ? (leerCantidad(_cant[l.id]!.text) ?? 0) : l.cantidadEfectiva;

  /// Total con lo que realmente recibe.
  int get _total => _lineas.fold(0, (s, l) {
        final q = _recibido(l);
        return s + l.copyWith(cantidadFinal: q, quitarConfirmacion: true).total;
      });

  int get _falta => (_total - widget.sena).clamp(0, _total);

  int get _pago => switch (_modo) {
        ModoPago.todo => _falta,
        ModoPago.parte => leerMonto(_monto.text) ?? 0,
        ModoPago.fiado => 0,
      };

  Future<void> _confirmar() async {
    if (!_form.currentState!.validate()) return;
    if (_parcial && _lineas.every((l) => _recibido(l) <= 0)) {
      return showSnack(context, 'Si no recibió nada, volvé y marcá "No recibió".', error: true);
    }
    setState(() => _guardando = true);
    try {
      final v = await context.read<VentaRepository>().entregar(
            widget.pedido.id,
            recibido: _parcial ? {for (final l in _lineas) l.id: _recibido(l)} : null,
            pago: PagoAlEntregar(monto: _pago, metodo: _metodo),
            notaRemision: _remision.text,
            clave: _clave.valor,
          );
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VentaScreen(id: v.id)));
    } catch (e) {
      registrarError('entregar', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    return Scaffold(
      appBar: AppBar(title: Text('Entregar · ${p.cliente.nombre}')),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 140),
          children: [
            Cuerpo(
              maxWidth: 720,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionTitle('¿Qué recibió el local?'),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Recibió todo'), icon: Icon(Icons.done_all)),
                    ButtonSegment(value: true, label: Text('Recibió una parte'), icon: Icon(Icons.rule)),
                  ],
                  selected: {_parcial},
                  onSelectionChanged: (v) => setState(() => _parcial = v.first),
                ),
                if (_parcial)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Lo que no recibió entra al stock con lo que pagaste al proveedor.', style: TextStyle(color: AppColors.muted)),
                  ),
                const SizedBox(height: 10),
                Card(
                  child: Column(children: [
                    for (var i = 0; i < _lineas.length; i++) ...[
                      if (i > 0) const Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_lineas[i].descripcion, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('${cantidad(_lineas[i].cantidadEfectiva)} ${_lineas[i].unidadTexto(_lineas[i].cantidadEfectiva)} × ${gs(_lineas[i].precio)}',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                            ]),
                          ),
                          if (_parcial)
                            SizedBox(
                              width: 110,
                              child: TextFormField(
                                controller: _cant[_lineas[i].id],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.right,
                                decoration: const InputDecoration(labelText: 'Recibió'),
                                validator: (v) {
                                  final q = leerCantidad(v ?? '');
                                  if (q == null || q < 0) return 'Revisá';
                                  if (q > _lineas[i].cantidadEfectiva + 0.0001) return 'Máx. ${cantidad(_lineas[i].cantidadEfectiva)}';
                                  return null;
                                },
                              ),
                            )
                          else
                            Text(gs(_lineas[i].total), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ],
                  ]),
                ),
                const SectionTitle('Cobro'),
                if (widget.sena > 0) ...[
                  Aviso('Ya dejó ${gs(widget.sena)} de seña: se descuenta solo.', icon: Icons.savings_outlined, color: AppColors.blue, fondo: AppColors.blueSoft),
                  const SizedBox(height: 10),
                ],
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
                  MontoField(
                    controller: _monto,
                    label: 'Cuánto pagó *',
                    validator: validarMonto(campo: 'el monto', max: _falta < 1 ? 1 : _falta),
                  ),
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
                  decoration: const InputDecoration(labelText: 'Nota de remisión N° (opcional)', hintText: 'Ej: 001-001-0000123'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Condición de venta: ${_pago >= _falta ? 'Contado' : 'Crédito'} · se emite con el timbrado vigente.',
                  style: const TextStyle(color: AppColors.muted),
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
            TotalDestacado(
              etiqueta: 'TOTAL A PAGAR',
              monto: _total,
              detalle: [
                if (widget.sena > 0) 'Seña ${gs(widget.sena)}',
                if (_pago > 0) 'Paga ${gs(_pago)}',
                if (_falta - _pago > 0) 'Queda debiendo ${gs(_falta - _pago)}',
              ].join(' · '),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _confirmar,
                icon: const Icon(Icons.receipt_long),
                label: Text(_guardando ? 'Guardando…' : 'Confirmar entrega y emitir factura'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
