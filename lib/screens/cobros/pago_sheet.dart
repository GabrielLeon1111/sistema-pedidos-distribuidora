import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/pago.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/cobro_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import 'recibo_screen.dart';

/// Registrar un pago (o una seña de un pedido). Al terminar abre el recibo.
Future<Pago?> registrarPago(
  BuildContext context, {
  required String clienteId,
  required String clienteNombre,
  required int maximo,
  String? ventaId,
  String? pedidoId,
  String? titulo,
}) async {
  final pago = await showModalBottomSheet<Pago>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PagoSheet(
      clienteId: clienteId,
      clienteNombre: clienteNombre,
      maximo: maximo,
      ventaId: ventaId,
      pedidoId: pedidoId,
      titulo: titulo ?? (pedidoId != null ? 'Seña o adelanto' : 'Registrar pago'),
    ),
  );
  if (pago != null && context.mounted) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReciboScreen(id: pago.id)));
  }
  return pago;
}

class _PagoSheet extends StatefulWidget {
  const _PagoSheet({
    required this.clienteId,
    required this.clienteNombre,
    required this.maximo,
    this.ventaId,
    this.pedidoId,
    required this.titulo,
  });
  final String clienteId;
  final String clienteNombre;
  final int maximo;
  final String? ventaId;
  final String? pedidoId;
  final String titulo;

  @override
  State<_PagoSheet> createState() => _PagoSheetState();
}

class _PagoSheetState extends State<_PagoSheet> {
  final _form = GlobalKey<FormState>();
  late final _monto = TextEditingController(text: widget.pedidoId == null && widget.maximo > 0 ? miles(widget.maximo) : '');
  final _nota = TextEditingController();
  String _metodo = 'efectivo';
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  @override
  void dispose() {
    _monto.dispose();
    _nota.dispose();
    super.dispose();
  }

  /// La misma en cada reintento: si se corta la señal, no se cobra dos veces.
  final _clave = ClaveOperacion();

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final hoy = DateTime.now();
      final esHoy = _fecha.year == hoy.year && _fecha.month == hoy.month && _fecha.day == hoy.day;
      final p = await context.read<CobroRepository>().registrar(
            clienteId: widget.clienteId,
            monto: leerMonto(_monto.text)!,
            metodo: _metodo,
            fecha: esHoy ? null : DateTime(_fecha.year, _fecha.month, _fecha.day, 12),
            nota: _nota.text,
            ventaId: widget.ventaId,
            pedidoId: widget.pedidoId,
            clave: _clave.valor,
          );
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      Navigator.pop(context, p);
    } catch (e) {
      registrarError('registrarPago', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(widget.titulo, style: Theme.of(context).textTheme.titleLarge),
                Text(widget.clienteNombre, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 6),
                Text(
                  widget.pedidoId != null ? 'Puede dejar hasta ${gs(widget.maximo)}' : 'Debe ${gs(widget.maximo)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                MontoField(
                  controller: _monto,
                  label: 'Monto *',
                  autofocus: true,
                  validator: validarMonto(campo: 'el monto', max: widget.maximo),
                ),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'efectivo', label: Text('Efectivo'), icon: Icon(Icons.payments_outlined)),
                    ButtonSegment(value: 'transferencia', label: Text('Transf.'), icon: Icon(Icons.account_balance_outlined)),
                  ],
                  selected: {_metodo},
                  onSelectionChanged: (v) => setState(() => _metodo = v.first),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: Text('Fecha: ${fechaCorta.format(_fecha)}'),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final f = await elegirFecha(context, inicial: _fecha, ultima: DateTime.now());
                      if (f != null) setState(() => _fecha = f);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nota,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(Largo.motivo),
                  decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Ej: pagó el encargado'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.check),
                  label: Text(_guardando ? 'Guardando…' : 'Registrar y ver recibo'),
                ),
                const SizedBox(height: 6),
                const Text('La app no cobra ni procesa pagos: solo los registra.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ]),
            ),
          ),
        ),
      );
}
