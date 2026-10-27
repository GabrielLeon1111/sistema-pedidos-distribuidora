import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/cliente.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/cliente_repository.dart';
import '../../security/registro_seguro.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';

/// Alta o edición de un local, con todo lo necesario para hacerle la factura.
Future<Cliente?> editarCliente(BuildContext context, [Cliente? cliente]) =>
    Navigator.of(context).push<Cliente>(MaterialPageRoute(builder: (_) => ClienteForm(cliente: cliente)));

class ClienteForm extends StatefulWidget {
  const ClienteForm({super.key, this.cliente});
  final Cliente? cliente;

  @override
  State<ClienteForm> createState() => _ClienteFormState();
}

class _ClienteFormState extends State<ClienteForm> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.cliente?.nombre);
  late final _razon = TextEditingController(text: widget.cliente?.razonSocial);
  late final _ruc = TextEditingController(text: widget.cliente?.ruc);
  late final _direccion = TextEditingController(text: widget.cliente?.direccion);
  late final _telefono = TextEditingController(text: widget.cliente?.telefono);
  late final _contacto = TextEditingController(text: widget.cliente?.contacto);
  late final _notas = TextEditingController(text: widget.cliente?.notas);
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [_nombre, _razon, _ruc, _direccion, _telefono, _contacto, _notas]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    String? t(TextEditingController c) {
      final v = limpiarTexto(c.text);
      return v.isEmpty ? null : v;
    }

    try {
      final c = await context.read<ClienteRepository>().guardar(Cliente(
            id: widget.cliente?.id ?? const Uuid().v4(),
            nombre: limpiarTexto(_nombre.text),
            razonSocial: t(_razon),
            ruc: t(_ruc),
            direccion: t(_direccion),
            telefono: t(_telefono),
            contacto: t(_contacto),
            notas: limpiarTexto(_notas.text, multilinea: true).isEmpty ? null : limpiarTexto(_notas.text, multilinea: true),
            activo: widget.cliente?.activo ?? true,
            creado: widget.cliente?.creado ?? DateTime.now(),
          ));
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      Navigator.pop(context, c);
    } catch (e) {
      registrarError('guardarCliente', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.cliente == null ? 'Nuevo local' : 'Editar local')),
        body: Form(
          key: _form,
          child: ListView(
            padding: EdgeInsets.fromLTRB(margenLateral(context), 8, margenLateral(context), 100),
            children: [
              Cuerpo(
                maxWidth: 640,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    controller: _nombre,
                    autofocus: widget.cliente == null,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: formatoTexto(Largo.nombre),
                    decoration: const InputDecoration(labelText: 'Nombre del local *', hintText: 'Ej: Despensa San Roque'),
                    validator: validarTexto(campo: 'el nombre del local', obligatorio: true, max: Largo.nombre),
                  ),
                  const SectionTitle('Datos para facturar'),
                  TextFormField(
                    controller: _razon,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: formatoTexto(Largo.nombre),
                    decoration: const InputDecoration(labelText: 'Razón social', hintText: 'Ej: Juan Pérez S.A.'),
                    validator: validarTexto(campo: 'la razón social', max: Largo.nombre),
                  ),
                  const SizedBox(height: 12),
                  FilaCampos(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ruc,
                        inputFormatters: formatoTexto(Largo.documento),
                        decoration: const InputDecoration(labelText: 'RUC o CI', hintText: 'Ej: 80012345-6'),
                        validator: validarDocumento,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _telefono,
                        keyboardType: TextInputType.phone,
                        inputFormatters: formatoTexto(Largo.telefono),
                        decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp', hintText: 'Ej: 0981 123456'),
                        validator: validarTelefono,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _direccion,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: formatoTexto(Largo.direccion),
                    decoration: const InputDecoration(labelText: 'Dirección'),
                    validator: validarTexto(campo: 'la dirección', max: Largo.direccion),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contacto,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: formatoTexto(Largo.nombre),
                    decoration: const InputDecoration(labelText: 'Persona de contacto', hintText: 'Ej: Carlos (encargado)'),
                    validator: validarTexto(campo: 'el contacto', max: Largo.nombre),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notas,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: formatoTexto(Largo.notas),
                    decoration: const InputDecoration(labelText: 'Notas', hintText: 'Ej: entregar por la mañana'),
                    validator: validarTexto(campo: 'las notas', max: Largo.notas, multilinea: true),
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
