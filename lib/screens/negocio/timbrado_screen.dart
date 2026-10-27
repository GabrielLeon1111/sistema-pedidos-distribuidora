import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/timbrado.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/timbrado_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';

/// Panel de timbrado: con cuál se factura hoy, cuántos números quedan y cuándo vence.
class TimbradoScreen extends StatelessWidget {
  const TimbradoScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Timbrado')),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'nuevo-timbrado',
          onPressed: () => _editar(context),
          icon: const Icon(Icons.add),
          label: const Text('Timbrado'),
        ),
        body: ReloadingFuture<List<Timbrado>>(
          contexto: 'timbrados',
          load: () => context.read<TimbradoRepository>().listar(),
          builder: (context, lista, reload) {
            final vigente = lista.where((t) => t.activo && t.vigente && !t.agotado).firstOrNull;
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 100),
                children: [
                  Cuerpo(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (vigente == null)
                        const Aviso(
                          'No hay un timbrado vigente: las entregas y ventas no van a poder emitir factura.',
                          icon: Icons.warning_amber_rounded,
                          color: AppColors.red,
                          fondo: AppColors.redSoft,
                        )
                      else ...[
                        if (vigente.fin.difference(DateTime.now()).inDays < 30 || vigente.disponibles < 100)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Aviso(
                              vigente.disponibles < 100
                                  ? 'Quedan solo ${miles(vigente.disponibles)} números de factura.'
                                  : 'El timbrado vence el ${fechaCorta.format(vigente.fin)}. Pedí el nuevo a tiempo.',
                            ),
                          ),
                        GrillaTarjetas(children: [
                          StatCard(label: 'Timbrado vigente', value: vigente.numero, detail: '${vigente.establecimiento}-${vigente.punto}', highlight: true),
                          StatCard(label: 'Próxima factura', value: numeroFactura(vigente.establecimiento, vigente.punto, vigente.siguiente)),
                          StatCard(label: 'Números disponibles', value: miles(vigente.disponibles)),
                          StatCard(label: 'Vence', value: fechaCorta.format(vigente.fin)),
                        ]),
                      ],
                      const SectionTitle('Timbrados cargados'),
                      if (lista.isEmpty)
                        const EmptyState(
                          icon: Icons.verified_outlined,
                          title: 'Todavía no cargaste ningún timbrado',
                          message: 'Cargá los datos tal como figuran en la constancia de la SET.',
                        )
                      else
                        Card(
                          child: Column(children: [
                            for (var i = 0; i < lista.length; i++) ...[
                              if (i > 0) const Divider(),
                              ListTile(
                                title: Text('N° ${lista[i].numero} · ${lista[i].establecimiento}-${lista[i].punto}'),
                                subtitle: Text(
                                  '${fechaCorta.format(lista[i].inicio)} al ${fechaCorta.format(lista[i].fin)} · '
                                  'del ${miles(lista[i].desde)} al ${miles(lista[i].hasta)} · próxima ${miles(lista[i].siguiente)}',
                                ),
                                trailing: _PillEstado(lista[i]),
                                onTap: () => _editar(context, lista[i]),
                              ),
                            ],
                          ]),
                        ),
                    ]),
                  ),
                ],
              ),
            );
          },
        ),
      );

  Future<void> _editar(BuildContext context, [Timbrado? t]) async {
    final guardado = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _TimbradoForm(timbrado: t)));
    if (guardado == true && context.mounted) context.read<RefreshBus>().changed();
  }
}

class _PillEstado extends StatelessWidget {
  const _PillEstado(this.t);
  final Timbrado t;

  @override
  Widget build(BuildContext context) {
    final (color, fondo) = switch (t.estadoTexto) {
      'Vigente' => (AppColors.green, AppColors.greenSoft),
      'Inactivo' => (AppColors.muted, AppColors.line),
      'Todavía no vigente' => (AppColors.blue, AppColors.blueSoft),
      _ => (AppColors.red, AppColors.redSoft),
    };
    return Pill(t.estadoTexto, color: color, background: fondo);
  }
}

class _TimbradoForm extends StatefulWidget {
  const _TimbradoForm({this.timbrado});
  final Timbrado? timbrado;

  @override
  State<_TimbradoForm> createState() => _TimbradoFormState();
}

class _TimbradoFormState extends State<_TimbradoForm> {
  final _form = GlobalKey<FormState>();
  late final t = widget.timbrado;
  late final _numero = TextEditingController(text: t?.numero);
  late final _establecimiento = TextEditingController(text: t?.establecimiento ?? '001');
  late final _punto = TextEditingController(text: t?.punto ?? '001');
  late final _desde = TextEditingController(text: '${t?.desde ?? 1}');
  late final _hasta = TextEditingController(text: '${t?.hasta ?? 9999999}');
  late final _siguiente = TextEditingController(text: '${t?.siguiente ?? 1}');
  late final _pie = TextEditingController(text: t?.pieImprenta);
  late DateTime? _inicio = t?.inicio;
  late DateTime? _fin = t?.fin;
  late bool _activo = t?.activo ?? true;
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [_numero, _establecimiento, _punto, _desde, _hasta, _siguiente, _pie]) {
      c.dispose();
    }
    super.dispose();
  }

  String? Function(String?) _digitos(int n, String campo) =>
      (v) => RegExp('^\\d{$n}\$').hasMatch((v ?? '').trim()) ? null : '$campo: $n dígitos';

  String? _entero(String? v) => int.tryParse((v ?? '').trim()) == null ? 'Escribí un número' : null;

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    if (_inicio == null || _fin == null) {
      showSnack(context, 'Elegí las fechas de vigencia.', error: true);
      return;
    }
    setState(() => _guardando = true);
    final repo = context.read<TimbradoRepository>();
    try {
      await repo.guardar(Timbrado(
        id: t?.id ?? repo.nuevoId(),
        numero: _numero.text.trim(),
        inicio: _inicio!,
        fin: _fin!,
        establecimiento: _establecimiento.text.trim(),
        punto: _punto.text.trim(),
        desde: int.parse(_desde.text.trim()),
        hasta: int.parse(_hasta.text.trim()),
        siguiente: int.parse(_siguiente.text.trim()),
        activo: _activo,
        creado: t?.creado ?? DateTime.now(),
        pieImprenta: limpiarTexto(_pie.text, multilinea: true).isEmpty ? null : limpiarTexto(_pie.text, multilinea: true),
      ));
      if (!mounted) return;
      showSnack(context, 'Timbrado guardado');
      Navigator.pop(context, true);
    } catch (e) {
      registrarError('guardarTimbrado', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _campoFecha(String etiqueta, DateTime? valor, ValueChanged<DateTime> elegido) => InkWell(
        onTap: () async {
          final d = await elegirFecha(context, inicial: valor, primera: DateTime(2020), ultima: DateTime(DateTime.now().year + 6));
          if (d != null) setState(() => elegido(d));
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: etiqueta, suffixIcon: const Icon(Icons.calendar_today_outlined)),
          child: Text(valor == null ? 'Elegir' : fechaCorta.format(valor)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final soloNumeros = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(title: Text(t == null ? 'Nuevo timbrado' : 'Editar timbrado')),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(margenLateral(context), 8, margenLateral(context), 100),
          children: [
            Cuerpo(
              maxWidth: 640,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Aviso('Copiá los datos exactamente como figuran en la constancia de timbrado de la SET.', color: AppColors.blue, fondo: AppColors.blueSoft),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _numero,
                  keyboardType: TextInputType.number,
                  inputFormatters: [...soloNumeros, LengthLimitingTextInputFormatter(8)],
                  decoration: const InputDecoration(labelText: 'Número de timbrado *', hintText: '8 dígitos'),
                  validator: _digitos(8, 'Número de timbrado'),
                ),
                const SizedBox(height: 12),
                FilaCampos(anchoMinimo: 0, children: [
                  Expanded(
                    child: TextFormField(
                      controller: _establecimiento,
                      keyboardType: TextInputType.number,
                      inputFormatters: [...soloNumeros, LengthLimitingTextInputFormatter(3)],
                      decoration: const InputDecoration(labelText: 'Establecimiento *', hintText: '001'),
                      validator: _digitos(3, 'Establecimiento'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _punto,
                      keyboardType: TextInputType.number,
                      inputFormatters: [...soloNumeros, LengthLimitingTextInputFormatter(3)],
                      decoration: const InputDecoration(labelText: 'Punto de expedición *', hintText: '001'),
                      validator: _digitos(3, 'Punto'),
                    ),
                  ),
                ]),
                const SectionTitle('Vigencia'),
                FilaCampos(anchoMinimo: 0, children: [
                  Expanded(child: _campoFecha('Desde *', _inicio, (d) => _inicio = d)),
                  const SizedBox(width: 12),
                  Expanded(child: _campoFecha('Hasta *', _fin, (d) => _fin = d)),
                ]),
                const SectionTitle('Numeración'),
                FilaCampos(anchoMinimo: 0, children: [
                  for (final (c, etiqueta) in [(_desde, 'Del'), (_hasta, 'Al'), (_siguiente, 'Próxima')]) ...[
                    if (c != _desde) const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: c,
                        keyboardType: TextInputType.number,
                        inputFormatters: [...soloNumeros, LengthLimitingTextInputFormatter(7)],
                        decoration: InputDecoration(labelText: '$etiqueta *'),
                        validator: _entero,
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 6),
                const Text(
                  '"Próxima" es el número de la siguiente factura. Si ya emitiste facturas a mano con este timbrado, poné el que sigue.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SectionTitle('Pie de la factura'),
                TextFormField(
                  controller: _pie,
                  maxLines: 3,
                  inputFormatters: formatoTexto(300),
                  decoration: const InputDecoration(
                    labelText: 'Datos de la imprenta',
                    hintText: 'Copialo del pie del talonario: habilitación, imprenta, RUC, teléfono, cantidad, rango y fecha',
                    hintMaxLines: 3,
                  ),
                  validator: validarTexto(campo: 'los datos de la imprenta', max: 300, multilinea: true),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usar para facturar'),
                  subtitle: const Text('Se factura con un solo timbrado a la vez: los demás quedan inactivos.'),
                  value: _activo,
                  onChanged: (v) => setState(() => _activo = v),
                ),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.check),
            label: Text(_guardando ? 'Guardando…' : 'Guardar'),
          ),
        ),
      ),
    );
  }
}
