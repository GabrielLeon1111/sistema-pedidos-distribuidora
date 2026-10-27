import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/clave_operacion.dart';
import '../../models/consolidado.dart';
import '../../providers/negocio_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/producto_repository.dart';
import '../../repositories/proveedor_repository.dart';
import '../../security/registro_seguro.dart';
import '../../services/mensajes.dart';
import '../../services/pdf_documentos.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/filtro_categorias.dart';
import '../../widgets/doc_actions.dart';
import '../../widgets/estados.dart';
import '../../widgets/reloading_future.dart';
import 'recepcion_screen.dart';

/// Hoja para el proveedor y, cuando llega la mercadería, la recepción.
class ConsolidadoScreen extends StatefulWidget {
  const ConsolidadoScreen({super.key, required this.id});
  final String id;

  @override
  State<ConsolidadoScreen> createState() => _ConsolidadoScreenState();
}

class _ConsolidadoScreenState extends State<ConsolidadoScreen> {
  bool _precios = false;

  /// Categoría de cada producto (por id): los productos se muestran separados por categoría.
  Map<String, String?> _categorias = const {};

  @override
  void initState() {
    super.initState();
    context
        .read<ProductoRepository>()
        .listar(incluirInactivos: true)
        .then((ps) {
          if (mounted) setState(() => _categorias = {for (final p in ps) p.id: p.categoria});
        })
        .catchError((Object e) => registrarError('categoriasConsolidado', e));
  }

  String _categoria(LineaConsolidado l) => (l.productoId == null ? null : _categorias[l.productoId]) ?? sinCategoria;

  Future<void> _anular(Consolidado c, Future<void> Function() reload) async {
    final m = await pedirMotivo(
      context,
      titulo: c.directa ? 'Anular la lista de compras N° ${nroDoc(c.numero)}' : 'Anular pedido N° ${nroDoc(c.numero)} a ${c.proveedorNombre}',
      ayuda: 'Las ${c.pedidoIds.length} notas de pedido vuelven a "cargadas": se pueden editar, anular o volver a pedir.',
    );
    if (m == null || !mounted) return;
    final clave = nuevaClave();
    final hecho = await runSafe(
      context,
      'anularConsolidado',
      () => context.read<ProveedorRepository>().anular(c.id, m, clave: clave),
      ok: c.directa ? 'Lista de compras anulada' : 'Pedido al proveedor anulado',
    );
    if (!hecho || !mounted) return;
    context.read<RefreshBus>().changed();
    await reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pedido al proveedor o compra')),
    body: ReloadingFuture<Consolidado>(
      contexto: 'consolidado',
      load: () => context.read<ProveedorRepository>().obtener(widget.id),
      builder: (context, c, reload) {
        final negocio = context.watch<NegocioProvider>().negocio;
        return ListView(
          padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 40),
          children: [
            Cuerpo(
              maxWidth: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: ListTile(
                      title: Text(
                        c.directa ? 'Mi lista de compras' : c.proveedorNombre,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      subtitle: Text(
                        'N° ${nroDoc(c.numero)} · ${fechaHora.format(c.fecha)} · ${c.pedidoIds.length} pedidos'
                        '${c.creadoPor == null ? '' : ' · ${c.creadoPor}'}',
                      ),
                      trailing: Pill(
                        c.recibido ? (c.directa ? 'Comprado' : 'Recibido') : (c.anulado ? 'Anulado' : (c.directa ? 'Por comprar' : 'Esperando')),
                        color: c.recibido ? AppColors.green : (c.anulado ? AppColors.red : AppColors.orange),
                      ),
                    ),
                  ),
                  if (c.anulado) ...[
                    const SizedBox(height: 10),
                    Aviso(
                      'Anulado${c.fechaAnulacion == null ? '' : ' el ${fechaHora.format(c.fechaAnulacion!)}'}'
                      '${c.anuladoPor == null ? '' : ' por ${c.anuladoPor}'}. Motivo: ${c.motivo ?? '—'}',
                      icon: Icons.block,
                      color: AppColors.red,
                      fondo: AppColors.redSoft,
                    ),
                  ],
                  if (c.esperando) ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecepcionScreen(consolidado: c))),
                      icon: Icon(c.directa ? Icons.shopping_cart_checkout : Icons.fact_check_outlined),
                      label: Text(c.directa ? 'Ir marcando lo que compré' : 'Llegó la mercadería: registrar recepción'),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: AppColors.red),
                      onPressed: () => _anular(c, reload),
                      icon: const Icon(Icons.block),
                      label: Text(c.directa ? 'Anular esta lista de compras' : 'Anular este pedido al proveedor'),
                    ),
                  ],
                  SectionTitle('Productos (${c.lineas.length})'),
                  for (final cat in categoriasDe(c.lineas.map(_categoria)))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Separados por categoría (el título solo si hay más de una).
                          if (categoriasDe(c.lineas.map(_categoria)).length > 1)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                              child: Text(
                                cat.toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.primary),
                              ),
                            ),
                          Card(
                            child: Column(
                              children: [
                                for (final (k, i) in [
                                  for (var i = 0; i < c.lineas.length; i++)
                                    if (_categoria(c.lineas[i]) == cat) i,
                                ].indexed) ...[
                                  if (k > 0) const Divider(),
                                  ExpansionTile(
                                    shape: const Border(),
                                    title: Text(c.lineas[i].descripcion, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    subtitle: Text(
                                      c.recibido
                                          ? '${c.lineas[i].recepcion.texto} · llegó ${cantidad(c.lineas[i].cantidadRecibida)} de ${cantidad(c.lineas[i].cantidad)}'
                                                '${c.lineas[i].precioCompra > 0 ? ' a ${gs(c.lineas[i].precioCompra)}' : ''}'
                                          : [
                                              '${c.lineas[i].detalle.length} locales',
                                              if (c.lineas[i].nota != null) 'Detalle: ${c.lineas[i].nota}',
                                            ].join(' · '),
                                      style: TextStyle(color: c.recibido ? colorRecepcion(c.lineas[i].recepcion) : AppColors.muted),
                                    ),
                                    trailing: Text(
                                      '${cantidad(c.lineas[i].cantidad)} ${textoForma(c.lineas[i].unidad, c.lineas[i].factor, c.lineas[i].cantidad)}',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                    ),
                                    children: [
                                      for (final d in c.lineas[i].detalle)
                                        ListTile(
                                          dense: true,
                                          title: Text(d.clienteNombre),
                                          subtitle: Text(['Pedido N° ${nroDoc(d.pedidoNumero)}', ?d.nota].join(' · ')),
                                          trailing: Text(
                                            d.asignado == null || d.asignado == d.cantidad
                                                ? cantidad(d.cantidad)
                                                : '${cantidad(d.asignado!)} de ${cantidad(d.cantidad)}',
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (c.recibido) ...[
                    const SizedBox(height: 10),
                    TotalDestacado(etiqueta: c.directa ? 'GASTADO EN LA COMPRA' : 'PAGADO AL PROVEEDOR', monto: c.totalCompra),
                    const SectionTitle('Recepción en PDF o imagen'),
                    DocActions(build: () => pdfRecepcion(c, negocio), fileName: archivoRecepcion(c)),
                  ],
                  SectionTitle(c.directa ? 'Lista de compras en PDF o imagen' : 'Nota de pedido para el proveedor'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _precios,
                    onChanged: (v) => setState(() => _precios = v),
                    title: const Text('Incluir precios de compra y total'),
                    subtitle: const Text('El último precio que pagaste de cada producto'),
                  ),
                  DocActions(
                    key: ValueKey('$_precios-${_categorias.length}'),
                    build: () => pdfConsolidado(c, negocio, conPrecios: _precios, categorias: _categorias),
                    fileName: archivoConsolidado(c),
                    // La lista de compras es para uno mismo: no se le manda a nadie.
                    shareText: c.directa ? null : mensajeProveedor(c, negocio.nombre),
                    telefono: c.directa ? null : c.proveedorTelefono,
                    destinatario: c.directa ? null : c.proveedorNombre,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
