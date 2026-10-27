import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cliente.dart';
import '../../repositories/cliente_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import 'cliente_form.dart';
import 'cliente_screen.dart';

/// Locales (clientes).
class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Clientes')),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'nuevo-cliente',
          onPressed: () => editarCliente(context),
          icon: const Icon(Icons.add),
          label: const Text('Local'),
        ),
        body: ReloadingFuture<List<Cliente>>(
          contexto: 'clientes',
          load: () => context.read<ClienteRepository>().listar(),
          builder: (context, todos, reload) {
            final lista = todos.where((c) => c.coincide(_q)).toList();
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 100),
                children: [
                  Cuerpo(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre, RUC o contacto'),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                      const SizedBox(height: 10),
                      if (lista.isEmpty)
                        EmptyState(
                          icon: Icons.storefront_outlined,
                          title: todos.isEmpty ? 'Todavía no hay locales' : 'No se encontró "$_q"',
                          message: todos.isEmpty ? 'Cargá los locales a los que les vendés.' : null,
                        )
                      else
                        Card(
                          child: Column(children: [
                            for (var i = 0; i < lista.length; i++) ...[
                              if (i > 0) const Divider(),
                              ListTile(
                                leading: const CircleAvatar(backgroundColor: AppColors.primarySoft, child: Icon(Icons.storefront, color: AppColors.primary)),
                                title: Text(lista[i].nombre),
                                subtitle: Text([lista[i].razonSocial, lista[i].ruc, lista[i].telefono].whereType<String>().join(' · ')),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClienteScreen(id: lista[i].id))),
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
}
