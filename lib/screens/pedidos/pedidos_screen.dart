import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/pedido.dart';
import '../../repositories/pedido_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/estado_sincronizacion.dart';
import '../../widgets/estados.dart';
import '../../widgets/reloading_future.dart';
import 'pedido_detalle_screen.dart';
import 'pedido_editor_screen.dart';

enum _Filtro {
  abiertos('Abiertos'),
  entregar('Para entregar'),
  cerrados('Cerrados'),
  todos('Todos');

  const _Filtro(this.texto);
  final String texto;
}

/// Notas de pedido de cada local.
class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  _Filtro _filtro = _Filtro.abiertos;
  String _q = '';

  bool _pasa(Pedido p) {
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty && !p.cliente.nombre.toLowerCase().contains(q) && !nroDoc(p.numero).contains(q)) return false;
    return switch (_filtro) {
      _Filtro.abiertos => !p.cerrado,
      _Filtro.entregar => !p.cerrado && (p.entregable || p.esperandoConfirmacion),
      _Filtro.cerrados => p.cerrado,
      _Filtro.todos => true,
    };
  }

  Future<void> _nuevo() => Navigator.push(context, MaterialPageRoute(builder: (_) => const PedidoEditorScreen()));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Pedidos')),
        floatingActionButton: FloatingActionButton.extended(onPressed: _nuevo, icon: const Icon(Icons.add), label: const Text('Nota de pedido')),
        body: ReloadingFuture<List<Pedido>>(
          contexto: 'pedidos',
          load: () => context.read<PedidoRepository>().listar(),
          builder: (context, todos, reload) {
            final lista = todos.where(_pasa).toList();
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                padding: EdgeInsets.fromLTRB(margenLateral(context), 0, margenLateral(context), 100),
                children: [
                  Cuerpo(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const EstadoSincronizacion(),
                      TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar local o número'),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final f in _Filtro.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(f.texto),
                                selected: _filtro == f,
                                onSelected: (_) => setState(() => _filtro = f),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      if (lista.isEmpty)
                        EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: todos.isEmpty ? 'Todavía no hay pedidos' : 'No hay pedidos con ese filtro',
                          message: todos.isEmpty ? 'Cargá la primera nota de pedido de un local.' : null,
                        )
                      else
                        for (final p in lista) ...[TarjetaPedido(p), const SizedBox(height: 8)],
                    ]),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class TarjetaPedido extends StatelessWidget {
  const TarjetaPedido(this.p, {super.key});
  final Pedido p;

  @override
  Widget build(BuildContext context) {
    final atrasado = !p.cerrado && p.fechaEntrega != null && p.fechaEntrega!.isBefore(inicioDia(DateTime.now()));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoDetalleScreen(id: p.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(p.cliente.nombre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Text(gs(p.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            const SizedBox(height: 4),
            Text(
              'N° ${nroDoc(p.numero)} · ${fechaHora.format(p.fecha)} · ${p.lineas.length} productos'
              '${p.vendedorNombre == null ? '' : ' · ${p.vendedorNombre}'}',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (p.errorSincronizacion != null)
                const Pill('No se pudo subir', color: AppColors.red)
              else if (p.sinSincronizar)
                const Pill('Sin sincronizar', color: AppColors.orange)
              else
                PillPedido(p),
              if (p.fechaEntrega != null && !p.cerrado)
                Pill('Entrega ${fechaCorta.format(p.fechaEntrega!)}', color: atrasado ? AppColors.red : AppColors.muted),
              if (p.lineas.any((l) => l.deStock)) const Pill('Usa stock', color: AppColors.blue),
            ]),
          ]),
        ),
      ),
    );
  }
}
