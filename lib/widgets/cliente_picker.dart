import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart';
import '../repositories/cliente_repository.dart';
import '../screens/clientes/cliente_form.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Elegir un local (con búsqueda) o crear uno nuevo.
Future<Cliente?> elegirCliente(BuildContext context) => showModalBottomSheet<Cliente>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ClientePicker(),
    );

class _ClientePicker extends StatefulWidget {
  const _ClientePicker();

  @override
  State<_ClientePicker> createState() => _ClientePickerState();
}

class _ClientePickerState extends State<_ClientePicker> {
  List<Cliente>? _todos;
  String _q = '';

  @override
  void initState() {
    super.initState();
    context.read<ClienteRepository>().listar().then((v) {
      if (mounted) setState(() => _todos = v);
    });
  }

  Future<void> _nuevo() async {
    final c = await editarCliente(context);
    if (c != null && mounted) Navigator.pop(context, c);
  }

  /// Completar o corregir los datos de un local ya cargado.
  Future<void> _editar(Cliente c) async {
    final editado = await editarCliente(context, c);
    if (editado == null || !mounted) return;
    setState(() => _todos = [for (final x in _todos ?? <Cliente>[]) x.id == editado.id ? editado : x]);
  }

  @override
  Widget build(BuildContext context) {
    final lista = (_todos ?? []).where((c) => c.coincide(_q)).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: Text('Elegí el local', style: Theme.of(context).textTheme.titleLarge)),
                TextButton.icon(onPressed: _nuevo, icon: const Icon(Icons.add), label: const Text('Nuevo')),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre, RUC o contacto'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _todos == null
                  ? const Center(child: CircularProgressIndicator())
                  : lista.isEmpty
                      ? EmptyState(
                          icon: Icons.storefront_outlined,
                          title: _q.isEmpty ? 'Todavía no hay locales' : 'No se encontró "$_q"',
                          action: FilledButton.icon(onPressed: _nuevo, icon: const Icon(Icons.add), label: const Text('Cargar local')),
                        )
                      : ListView.separated(
                          itemCount: lista.length,
                          separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                          itemBuilder: (_, i) {
                            final c = lista[i];
                            return ListTile(
                              leading: const CircleAvatar(backgroundColor: AppColors.primarySoft, child: Icon(Icons.storefront, color: AppColors.primary)),
                              title: Text(c.nombre),
                              subtitle: Text([c.razonSocial, c.ruc, c.contacto].whereType<String>().join(' · ')),
                              trailing: IconButton(
                                tooltip: 'Editar datos del local',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editar(c),
                              ),
                              onTap: () => Navigator.pop(context, c),
                            );
                          },
                        ),
            ),
          ]),
        ),
      ),
    );
  }
}
