import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/gasto.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/gasto_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import '../../widgets/periodo.dart';
import '../../widgets/reloading_future.dart';

/// Gastos del negocio por categoría, con reporte diario, semanal y mensual.
class GastosScreen extends StatefulWidget {
  const GastosScreen({super.key});

  @override
  State<GastosScreen> createState() => _GastosScreenState();
}

class _GastosScreenState extends State<GastosScreen> {
  PeriodoElegido _periodo = PeriodoElegido.de(TipoPeriodo.mes);
  String? _categoria;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Gastos')),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'gasto',
          onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const _NuevoGasto()),
          icon: const Icon(Icons.add),
          label: const Text('Gasto'),
        ),
        body: ReloadingFuture<List<Gasto>>(
          key: ValueKey('${_periodo.desde}${_periodo.hasta}'),
          contexto: 'gastos',
          load: () => context.read<GastoRepository>().listar(desde: inicioDia(_periodo.desde), hasta: finDia(_periodo.hasta)),
          builder: (context, todos, reload) {
            final validos = todos.where((g) => !g.anulado).toList();
            final porCat = <String, int>{};
            for (final g in validos) {
              porCat[g.categoria] = (porCat[g.categoria] ?? 0) + g.monto;
            }
            final cats = porCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            final total = validos.fold<int>(0, (s, g) => s + g.monto);
            final lista = _categoria == null ? todos : todos.where((g) => g.categoria == _categoria).toList();
            // Por día
            final porDia = <DateTime, int>{};
            for (final g in validos.where((g) => _categoria == null || g.categoria == _categoria)) {
              final d = inicioDia(g.fecha);
              porDia[d] = (porDia[d] ?? 0) + g.monto;
            }
            final dias = porDia.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
            return ListView(
              padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 100),
              children: [
                Cuerpo(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SelectorPeriodo(valor: _periodo, onChanged: (p) => setState(() => _periodo = p)),
                    const SizedBox(height: 12),
                    StatCard(label: 'Total de gastos', value: gs(total), detail: '${validos.length} gastos', icon: Icons.receipt_long_outlined, highlight: true),
                    if (cats.isNotEmpty) ...[
                      const SectionTitle('Por categoría'),
                      Card(
                        child: Column(children: [
                          for (final c in cats)
                            ListTile(
                              dense: true,
                              selected: _categoria == c.key,
                              title: Text(c.key),
                              subtitle: LinearProgressIndicator(value: total == 0 ? 0 : c.value / total, minHeight: 4, backgroundColor: AppColors.line),
                              trailing: Text(gs(c.value), style: const TextStyle(fontWeight: FontWeight.w800)),
                              onTap: () => setState(() => _categoria = _categoria == c.key ? null : c.key),
                            ),
                        ]),
                      ),
                    ],
                    if (dias.length > 1) ...[
                      const SectionTitle('Por día'),
                      Card(
                        child: Column(children: [
                          for (final d in dias)
                            ListTile(dense: true, title: Text(fechaLarga.format(d.key)), trailing: Text(gs(d.value), style: const TextStyle(fontWeight: FontWeight.w700))),
                        ]),
                      ),
                    ],
                    SectionTitle(_categoria == null ? 'Detalle' : 'Detalle · $_categoria'),
                    if (lista.isEmpty)
                      const EmptyState(icon: Icons.receipt_long_outlined, title: 'No hay gastos en este período')
                    else
                      Card(
                        child: Column(children: [
                          for (final g in lista)
                            ListTile(
                              title: Text(g.categoria, style: TextStyle(decoration: g.anulado ? TextDecoration.lineThrough : null)),
                              subtitle: Text([
                                fechaHora.format(g.fecha),
                                ?g.descripcion,
                                if (g.factura != null) 'Fact. ${g.factura}',
                                if (g.anulado) 'Anulado: ${g.motivoAnulacion}',
                              ].join(' · ')),
                              trailing: Text(gs(g.monto), style: TextStyle(fontWeight: FontWeight.w800, color: g.anulado ? AppColors.muted : AppColors.ink)),
                              onLongPress: g.anulado
                                  ? null
                                  : () async {
                                      final m = await pedirMotivo(context, titulo: 'Anular gasto', ayuda: 'Deja de restar en la ganancia, pero queda en el historial.');
                                      if (m == null || !context.mounted) return;
                                      final ok = await runSafe(context, 'anularGasto', () => context.read<GastoRepository>().anular(g.id, m, clave: nuevaClave()), ok: 'Gasto anulado');
                                      if (ok && context.mounted) context.read<RefreshBus>().changed();
                                    },
                            ),
                        ]),
                      ),
                    const SizedBox(height: 6),
                    const Text('Mantené apretado un gasto para anularlo.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ]),
                ),
              ],
            );
          },
        ),
      );
}

class _NuevoGasto extends StatefulWidget {
  const _NuevoGasto();

  @override
  State<_NuevoGasto> createState() => _NuevoGastoState();
}

class _NuevoGastoState extends State<_NuevoGasto> {
  final _form = GlobalKey<FormState>();
  String _categoria = categoriasGasto.first;
  final _monto = TextEditingController();
  final _desc = TextEditingController();
  final _factura = TextEditingController();
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  /// La misma en cada reintento: si se corta la señal, el gasto no se carga dos veces.
  final _clave = ClaveOperacion();

  @override
  void dispose() {
    _monto.dispose();
    _desc.dispose();
    _factura.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final ahora = DateTime.now();
      final f = DateTime(_fecha.year, _fecha.month, _fecha.day, ahora.hour, ahora.minute);
      await context.read<GastoRepository>().registrar(
            categoria: _categoria,
            monto: leerMonto(_monto.text)!,
            fecha: f.isAfter(ahora) ? ahora : f,
            descripcion: _desc.text,
            factura: _factura.text,
            clave: _clave.valor,
          );
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      Navigator.pop(context);
    } catch (e) {
      registrarError('gasto', e);
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
                Text('Nuevo gasto', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _categoria,
                  decoration: const InputDecoration(labelText: 'Categoría *'),
                  items: [for (final c in categoriasGasto) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _categoria = v ?? _categoria),
                ),
                const SizedBox(height: 12),
                MontoField(controller: _monto, label: 'Monto *', autofocus: true, validator: validarMonto()),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _desc,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(Largo.descripcion),
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)', hintText: 'Ej: combustible del reparto'),
                ),
                const SizedBox(height: 12),
                FilaCampos(anchoMinimo: 360, children: [
                  Expanded(
                    child: TextFormField(
                      controller: _factura,
                      inputFormatters: formatoTexto(Largo.factura),
                      decoration: const InputDecoration(labelText: 'N° de factura (opcional)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final f = await elegirFecha(context, inicial: _fecha, ultima: DateTime.now());
                        if (f != null) setState(() => _fecha = f);
                      },
                      icon: const Icon(Icons.event),
                      label: Text(fechaCorta.format(_fecha)),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: _guardando ? null : _guardar, icon: const Icon(Icons.check), label: Text(_guardando ? 'Guardando…' : 'Guardar gasto')),
              ]),
            ),
          ),
        ),
      );
}
