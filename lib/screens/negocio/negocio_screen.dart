import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/negocio.dart';
import '../../providers/negocio_provider.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';

/// Nombre, RUC, logo y los datos que salen en la factura y en las notas.
class NegocioScreen extends StatefulWidget {
  const NegocioScreen({super.key});

  @override
  State<NegocioScreen> createState() => _NegocioScreenState();
}

class _NegocioScreenState extends State<NegocioScreen> {
  /// El logo va dentro de los datos: más grande hace pesados los PDF.
  static const _logoMaxBytes = 400 * 1024;

  final _form = GlobalKey<FormState>();
  late final Negocio n = context.read<NegocioProvider>().negocio;
  late final _nombre = TextEditingController(text: n.nombre);
  late final _rubro = TextEditingController(text: n.rubro);
  late final _propietario = TextEditingController(text: n.propietario);
  late final _actividades = TextEditingController(text: n.actividades);
  late final _ruc = TextEditingController(text: n.ruc);
  late final _telefono = TextEditingController(text: n.telefono);
  late final _direccion = TextEditingController(text: n.direccion);
  late final _ciudad = TextEditingController(text: n.ciudad);
  late final _email = TextEditingController(text: n.email);
  late final _notaPie = TextEditingController(text: n.notaPie);
  late String? _logoBase64 = n.logoBase64;
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [_nombre, _rubro, _propietario, _actividades, _ruc, _telefono, _direccion, _ciudad, _email, _notaPie]) {
      c.dispose();
    }
    super.dispose();
  }

  Uint8List? get _logo => Negocio(logoBase64: _logoBase64).logo;

  Future<void> _elegirLogo() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 85);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _logoMaxBytes) {
        showSnack(context, 'La imagen es muy pesada. Elegí una más chica (hasta 400 KB).', error: true);
        return;
      }
      setState(() => _logoBase64 = base64Encode(bytes));
    } catch (e) {
      registrarError('elegirLogo', e);
      if (mounted) showSnack(context, 'No se pudo abrir la imagen.', error: true);
    }
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    String? t(TextEditingController c, {bool multilinea = false}) {
      final v = limpiarTexto(c.text, multilinea: multilinea);
      return v.isEmpty ? null : v;
    }

    final ok = await runSafe(
      context,
      'guardarNegocio',
      () => context.read<NegocioProvider>().guardar(Negocio(
            nombre: limpiarTexto(_nombre.text),
            rubro: limpiarTexto(_rubro.text),
            propietario: t(_propietario),
            actividades: t(_actividades, multilinea: true),
            ruc: t(_ruc),
            telefono: t(_telefono),
            direccion: t(_direccion),
            ciudad: t(_ciudad),
            email: t(_email),
            logoBase64: _logoBase64,
            notaPie: t(_notaPie, multilinea: true),
          )),
      ok: 'Datos del negocio guardados',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logo = _logo;
    return Scaffold(
      appBar: AppBar(title: const Text('Datos del negocio')),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(margenLateral(context), 8, margenLateral(context), 100),
          children: [
            Cuerpo(
              maxWidth: 640,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          border: Border.all(color: AppColors.line),
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: logo == null
                            ? const Icon(Icons.image_outlined, color: AppColors.muted, size: 36)
                            : Image.memory(logo, fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Logo', style: TextStyle(fontWeight: FontWeight.w700)),
                          const Text('Sale arriba en las facturas, notas y recibos.', style: TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, children: [
                            OutlinedButton.icon(
                              onPressed: _elegirLogo,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: Text(logo == null ? 'Elegir' : 'Cambiar'),
                            ),
                            if (logo != null)
                              TextButton(onPressed: () => setState(() => _logoBase64 = null), child: const Text('Quitar')),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                ),
                const SectionTitle('Negocio'),
                TextFormField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: formatoTexto(Largo.nombre),
                  decoration: const InputDecoration(labelText: 'Nombre del negocio *'),
                  validator: validarTexto(campo: 'el nombre del negocio', obligatorio: true, max: Largo.nombre),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _rubro,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(Largo.titulo),
                  decoration: const InputDecoration(labelText: 'Rubro *', hintText: 'Ej: Distribuidora de productos de limpieza'),
                  validator: validarTexto(campo: 'el rubro', obligatorio: true, max: Largo.titulo),
                ),
                const SectionTitle('Para la factura'),
                TextFormField(
                  controller: _propietario,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: formatoTexto(Largo.nombre),
                  decoration: const InputDecoration(labelText: 'Propietario', hintText: 'Sale como "de Nombre Apellido"'),
                  validator: validarTexto(campo: 'el propietario', max: Largo.nombre),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _actividades,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(Largo.descripcion),
                  decoration: const InputDecoration(labelText: 'Actividades económicas', hintText: 'Como figuran en la constancia de RUC'),
                  validator: validarTexto(campo: 'las actividades', max: Largo.descripcion, multilinea: true),
                ),
                const SizedBox(height: 12),
                FilaCampos(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ruc,
                      inputFormatters: formatoTexto(Largo.documento),
                      decoration: const InputDecoration(labelText: 'RUC', hintText: 'Ej: 4567890-1'),
                      validator: validarRuc,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _telefono,
                      keyboardType: TextInputType.phone,
                      inputFormatters: formatoTexto(Largo.telefono),
                      decoration: const InputDecoration(labelText: 'Teléfono'),
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
                FilaCampos(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ciudad,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: formatoTexto(Largo.ciudad),
                      decoration: const InputDecoration(labelText: 'Ciudad'),
                      validator: validarTexto(campo: 'la ciudad', max: Largo.ciudad),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      inputFormatters: formatoTexto(Largo.email),
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: validarEmail,
                    ),
                  ),
                ]),
                const SectionTitle('Documentos'),
                TextFormField(
                  controller: _notaPie,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(Largo.notas),
                  decoration: const InputDecoration(labelText: 'Nota al pie', hintText: 'Ej: Gracias por su compra'),
                  validator: validarTexto(campo: 'la nota', max: Largo.notas, multilinea: true),
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
