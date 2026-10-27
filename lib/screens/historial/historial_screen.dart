import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/historial.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/historial_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/periodo.dart';
import '../../widgets/reloading_future.dart';
import '../cobros/recibo_screen.dart';
import '../pedidos/pedido_detalle_screen.dart';
import '../proveedor/consolidado_screen.dart';
import '../ventas/venta_screen.dart';

/// Documentos (se hayan enviado o no) y registro de cambios.
class HistorialScreen extends StatelessWidget {
  const HistorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final esAdmin = context.select<AuthProvider, bool>((a) => a.esAdmin);
    if (!esAdmin) return Scaffold(appBar: AppBar(title: const Text('Mis notas de pedido')), body: const _Documentos());
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Historial'), bottom: const TabBar(tabs: [Tab(text: 'Documentos'), Tab(text: 'Cambios')])),
        body: const TabBarView(children: [_Documentos(), _Cambios()]),
      ),
    );
  }
}

class _Documentos extends StatefulWidget {
  const _Documentos();

  @override
  State<_Documentos> createState() => _DocumentosState();
}

class _DocumentosState extends State<_Documentos> {
  TipoDocumento? _tipo;
  String _q = '';

  IconData _icono(TipoDocumento t) => switch (t) {
        TipoDocumento.notaPedido => Icons.receipt_long_outlined,
        TipoDocumento.notaVenta => Icons.request_quote_outlined,
        TipoDocumento.consolidado => Icons.local_shipping_outlined,
        TipoDocumento.recepcion => Icons.fact_check_outlined,
        TipoDocumento.recibo => Icons.payments_outlined,
      };

  void _abrir(Documento d) {
    final Widget w = switch (d.tipo) {
      TipoDocumento.notaPedido => PedidoDetalleScreen(id: d.id),
      TipoDocumento.notaVenta => VentaScreen(id: d.id),
      TipoDocumento.consolidado || TipoDocumento.recepcion => ConsolidadoScreen(id: d.id),
      TipoDocumento.recibo => ReciboScreen(id: d.id),
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => w));
  }

  @override
  Widget build(BuildContext context) {
    final esAdmin = context.select<AuthProvider, bool>((a) => a.esAdmin);
    return ReloadingFuture<List<Documento>>(
      key: ValueKey(_tipo),
      contexto: 'documentos',
      load: () => context.read<HistorialRepository>().documentos(tipo: _tipo),
      builder: (context, docs, reload) {
        final q = _q.trim().toLowerCase();
        final lista = q.isEmpty ? docs : docs.where((d) => d.titulo.toLowerCase().contains(q) || nroDoc(d.numero).contains(q)).toList();
        return ListView(
          padding: EdgeInsets.fromLTRB(margenLateral(context), 10, margenLateral(context), 32),
          children: [
            Cuerpo(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por local, proveedor o número'),
                  onChanged: (v) => setState(() => _q = v),
                ),
                if (esAdmin) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final t in TipoDocumento.values) ...[
                        ChoiceChip(
                          label: Text(t == TipoDocumento.notaVenta ? 'Factura' : t.texto),
                          selected: _tipo == t,
                          onSelected: (v) => setState(() => _tipo = v ? t : null),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ]),
                  ),
                ],
                const SizedBox(height: 10),
                if (lista.isEmpty)
                  const EmptyState(icon: Icons.folder_open, title: 'No hay documentos')
                else
                  Card(
                    child: Column(children: [
                      for (var i = 0; i < lista.length; i++) ...[
                        if (i > 0) const Divider(),
                        ListTile(
                          leading: Icon(_icono(lista[i].tipo), color: lista[i].anulado ? AppColors.red : AppColors.primary),
                          title: Text(
                            '${lista[i].tipo == TipoDocumento.notaVenta ? 'Factura' : lista[i].tipo.texto} N° ${nroDoc(lista[i].numero)} · ${lista[i].titulo}',
                            style: TextStyle(decoration: lista[i].anulado ? TextDecoration.lineThrough : null),
                          ),
                          subtitle: Text('${fechaHora.format(lista[i].fecha)} · ${lista[i].detalle}'),
                          trailing: lista[i].monto == null ? null : Text(gs(lista[i].monto!), style: const TextStyle(fontWeight: FontWeight.w700)),
                          onTap: () => _abrir(lista[i]),
                        ),
                      ],
                    ]),
                  ),
              ]),
            ),
          ],
        );
      },
    );
  }
}

class _Cambios extends StatefulWidget {
  const _Cambios();

  @override
  State<_Cambios> createState() => _CambiosState();
}

class _CambiosState extends State<_Cambios> {
  PeriodoElegido _periodo = PeriodoElegido.de(TipoPeriodo.semana);
  String? _area;
  String? _persona;
  bool _importantes = false;

  @override
  Widget build(BuildContext context) => ReloadingFuture<(List<Cambio>, List<String>)>(
        key: ValueKey('${_periodo.desde}${_periodo.hasta}$_area$_persona$_importantes'),
        contexto: 'cambios',
        load: () async {
          final repo = context.read<HistorialRepository>();
          return (
            await repo.cambios(
              desde: inicioDia(_periodo.desde),
              hasta: finDia(_periodo.hasta),
              area: _area,
              usuario: _persona,
              soloImportantes: _importantes,
            ),
            await repo.personas(),
          );
        },
        builder: (context, d, reload) {
          final (cambios, personas) = d;
          return ListView(
            padding: EdgeInsets.fromLTRB(margenLateral(context), 10, margenLateral(context), 32),
            children: [
              Cuerpo(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SelectorPeriodo(valor: _periodo, onChanged: (p) => setState(() => _periodo = p)),
                  const SizedBox(height: 10),
                  FilaCampos(anchoMinimo: 420, children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: _area,
                        decoration: const InputDecoration(labelText: 'Área'),
                        items: [const DropdownMenuItem(value: null, child: Text('Todas')), for (final a in Area.todas) DropdownMenuItem(value: a, child: Text(a))],
                        onChanged: (v) => setState(() => _area = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: personas.contains(_persona) ? _persona : null,
                        decoration: const InputDecoration(labelText: 'Persona'),
                        items: [const DropdownMenuItem(value: null, child: Text('Todas')), for (final p in personas) DropdownMenuItem(value: p, child: Text(p))],
                        onChanged: (v) => setState(() => _persona = v),
                      ),
                    ),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _importantes,
                    onChanged: (v) => setState(() => _importantes = v),
                    title: const Text('Solo lo importante'),
                    subtitle: const Text('Anulaciones, rechazos, cambios de precio, ajustes…'),
                  ),
                  if (cambios.isEmpty)
                    const EmptyState(icon: Icons.history, title: 'Sin cambios en el período')
                  else
                    Card(
                      child: Column(children: [
                        for (var i = 0; i < cambios.length; i++) ...[
                          if (i > 0) const Divider(),
                          ListTile(
                            dense: true,
                            leading: Icon(cambios[i].importante ? Icons.priority_high_rounded : Icons.circle, size: cambios[i].importante ? 22 : 10,
                                color: cambios[i].importante ? AppColors.orange : AppColors.muted),
                            title: Text('${cambios[i].accion} · ${cambios[i].area}'),
                            subtitle: Text('${cambios[i].detalle}\n${fechaHora.format(cambios[i].fecha)} · ${cambios[i].usuarioNombre}'),
                            isThreeLine: true,
                          ),
                        ],
                      ]),
                    ),
                  const SizedBox(height: 8),
                  const Text('El historial no se puede editar ni borrar.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
            ],
          );
        },
      );
}
