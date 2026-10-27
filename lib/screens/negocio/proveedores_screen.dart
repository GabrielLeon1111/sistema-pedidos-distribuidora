import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/proveedor.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/proveedor_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';

/// A quién se le pide la mercadería. Los inactivos no salen al cargar productos.
class ProveedoresScreen extends StatelessWidget {
  const ProveedoresScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Proveedores')),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'nuevo-proveedor',
          onPressed: () => _editar(context),
          icon: const Icon(Icons.add),
          label: const Text('Proveedor'),
        ),
        body: ReloadingFuture<List<Proveedor>>(
          contexto: 'proveedores',
          load: () => context.read<ProveedorRepository>().listar(incluirInactivos: true),
          builder: (context, lista, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 100),
              children: [
                Cuerpo(
                  child: lista.isEmpty
                      ? const EmptyState(icon: Icons.local_shipping_outlined, title: 'Todavía no hay proveedores')
                      : Card(
                          child: Column(children: [
                            for (var i = 0; i < lista.length; i++) ...[
                              if (i > 0) const Divider(),
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: lista[i].activo ? AppColors.primarySoft : AppColors.line,
                                  child: Icon(Icons.local_shipping_outlined, color: lista[i].activo ? AppColors.primary : AppColors.muted),
                                ),
                                title: Text(lista[i].nombre, style: TextStyle(color: lista[i].activo ? null : AppColors.muted)),
                                subtitle: Text([lista[i].telefono, lista[i].notas].whereType<String>().join(' · ')),
                                trailing: lista[i].activo
                                    ? const Icon(Icons.edit_outlined)
                                    : const Pill('Inactivo', color: AppColors.red, background: AppColors.redSoft),
                                onTap: () => _editar(context, lista[i]),
                              ),
                            ],
                          ]),
                        ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _editar(BuildContext context, [Proveedor? p]) async {
    final guardado = await showDialog<bool>(context: context, builder: (_) => _ProveedorDialog(proveedor: p));
    if (guardado == true && context.mounted) context.read<RefreshBus>().changed();
  }
}

class _ProveedorDialog extends StatefulWidget {
  const _ProveedorDialog({this.proveedor});
  final Proveedor? proveedor;

  @override
  State<_ProveedorDialog> createState() => _ProveedorDialogState();
}

class _ProveedorDialogState extends State<_ProveedorDialog> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.proveedor?.nombre);
  late final _telefono = TextEditingController(text: widget.proveedor?.telefono);
  late final _notas = TextEditingController(text: widget.proveedor?.notas);
  late bool _activo = widget.proveedor?.activo ?? true;
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [_nombre, _telefono, _notas]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final repo = context.read<ProveedorRepository>();
    final notas = limpiarTexto(_notas.text, multilinea: true);
    final tel = limpiarTexto(_telefono.text);
    final ok = await runSafe(
      context,
      'guardarProveedor',
      () => repo.guardar(Proveedor(
        id: widget.proveedor?.id ?? repo.nuevoId(),
        nombre: limpiarTexto(_nombre.text),
        telefono: tel.isEmpty ? null : tel,
        notas: notas.isEmpty ? null : notas,
        activo: _activo,
      )),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.proveedor == null ? 'Nuevo proveedor' : 'Editar proveedor'),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _nombre,
                autofocus: widget.proveedor == null,
                textCapitalization: TextCapitalization.words,
                inputFormatters: formatoTexto(Largo.proveedor),
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: validarTexto(campo: 'el nombre', obligatorio: true, max: Largo.proveedor),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefono,
                keyboardType: TextInputType.phone,
                inputFormatters: formatoTexto(Largo.telefono),
                decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp', hintText: 'Para mandarle el pedido'),
                validator: validarTelefono,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notas,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: formatoTexto(Largo.notas),
                decoration: const InputDecoration(labelText: 'Notas', hintText: 'Ej: pedir antes de las 10'),
                validator: validarTexto(campo: 'las notas', max: Largo.notas, multilinea: true),
              ),
              if (widget.proveedor != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  subtitle: const Text('Si lo desactivás no sale al cargar productos'),
                  value: _activo,
                  onChanged: (v) => setState(() => _activo = v),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: _guardando ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: _guardando ? null : _guardar, child: Text(_guardando ? 'Guardando…' : 'Guardar')),
        ],
      );
}
