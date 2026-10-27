import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/cliente.dart';
import '../../models/pago.dart';
import '../../models/venta.dart';
import '../../providers/negocio_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/cliente_repository.dart';
import '../../repositories/cobro_repository.dart';
import '../../repositories/venta_repository.dart';
import '../../services/mensajes.dart';
import '../../models/negocio.dart';
import '../../services/pdf_documentos.dart';
import '../../services/pdf_factura.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/doc_actions.dart';
import '../../widgets/estados.dart';
import '../../widgets/reloading_future.dart';
import '../cobros/pago_sheet.dart';
import '../cobros/recibo_screen.dart';

/// Venta facturada: la factura en PDF o imagen, lo pagado, el saldo y los pagos.
class VentaScreen extends StatelessWidget {
  const VentaScreen({super.key, required this.id});
  final String id;

  Future<(Venta, Cliente?, List<Pago>)> _cargar(BuildContext context) async {
    final ventas = context.read<VentaRepository>();
    final clientes = context.read<ClienteRepository>();
    final cobros = context.read<CobroRepository>();
    final v = await ventas.obtener(id);
    final c = await clientes.obtener(v.clienteId);
    final pagos = (await cobros.pagos(clienteId: v.clienteId))
        .where((p) => p.aplicaciones.any((a) => a.ventaId == v.id))
        .toList();
    return (v, c, pagos);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Factura')),
        body: ReloadingFuture<(Venta, Cliente?, List<Pago>)>(
          contexto: 'venta',
          load: () => _cargar(context),
          builder: (context, d, reload) {
            final (v, cliente, pagos) = d;
            final negocio = context.watch<NegocioProvider>().negocio;
            final f = v.factura;
            return ListView(
              padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 40),
              children: [
                Cuerpo(
                  maxWidth: 720,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text(f == null ? 'Nota de venta N° ${nroDoc(v.numero)}' : 'Factura ${f.numeroCompleto}',
                                  style: Theme.of(context).textTheme.titleLarge),
                            ),
                            PillPago(v.estadoPago),
                          ]),
                          const SizedBox(height: 4),
                          Text(v.cliente.nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Text(
                            [
                              fechaHora.format(v.fecha),
                              if (f != null) f.contado ? 'Contado' : 'Crédito',
                              if (v.pedidoNumero != null) 'Pedido N° ${nroDoc(v.pedidoNumero!)}' else 'Venta directa',
                            ].join(' · '),
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          if (f != null) Text('Timbrado ${f.timbrado}', style: const TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 10),
                          for (final l in v.lineas)
                            KeyValueRow('${cantidad(l.cantidad)} × ${l.descripcion}', gs(l.total)),
                          const Divider(),
                          KeyValueRow('Total', gs(v.total), bold: true),
                          KeyValueRow('Pagado', gs(v.pagado), valueColor: AppColors.green),
                          KeyValueRow('Saldo', gs(v.saldo), bold: true, valueColor: v.saldo > 0 ? AppColors.red : AppColors.green),
                          if (v.entregaParcial) const Padding(padding: EdgeInsets.only(top: 6), child: Pill('Entrega parcial', color: AppColors.orange)),
                          if (v.anulada) KeyValueRow('Motivo de anulación', v.motivoAnulacion ?? '—', valueColor: AppColors.red),
                        ]),
                      ),
                    ),
                    if (v.saldo > 0 && !v.anulada) ...[
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => registrarPago(context, clienteId: v.clienteId, clienteNombre: v.cliente.nombre, maximo: v.saldo, ventaId: v.id),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Registrar pago'),
                      ),
                    ],
                    const SectionTitle('Imprimir o enviar'),
                    _Comprobantes(venta: v, negocio: negocio, cliente: cliente),
                    if (pagos.isNotEmpty) ...[
                      const SectionTitle('Pagos'),
                      Card(
                        child: Column(children: [
                          for (final p in pagos)
                            ListTile(
                              leading: const Icon(Icons.receipt_outlined),
                              title: Text('${gs(p.aplicaciones.firstWhere((a) => a.ventaId == v.id).monto)} · ${metodoPagoTexto(p.metodo)}'),
                              subtitle: Text('Recibo N° ${nroDoc(p.numero)} · ${fechaCorta.format(p.fecha)}${p.esSena ? ' · seña' : ''}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReciboScreen(id: p.id))),
                            ),
                        ]),
                      ),
                    ],
                    if (!v.anulada) ...[
                      const SizedBox(height: 24),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: AppColors.red),
                        onPressed: () async {
                          final m = await pedirMotivo(context,
                              titulo: 'Anular factura',
                              ayuda: 'La mercadería vuelve al stock y lo pagado queda a favor del local. El número de factura no se reutiliza.');
                          if (m == null || !context.mounted) return;
                          final ok = await runSafe(context, 'anularVenta', () => context.read<VentaRepository>().anular(v.id, m, clave: nuevaClave()), ok: 'Factura anulada');
                          if (ok && context.mounted) context.read<RefreshBus>().changed();
                        },
                        icon: const Icon(Icons.block),
                        label: const Text('Anular factura'),
                      ),
                    ],
                  ]),
                ),
              ],
            );
          },
        ),
      );
}

enum _Doc { factura, notaVenta }

/// Elegir qué se imprime o se manda (factura o nota de venta), y si van dos
/// copias: una para el comprador y otra para el negocio. Con pocos productos
/// las dos salen en una sola hoja, mitad y mitad, para cortar un solo papel.
class _Comprobantes extends StatefulWidget {
  const _Comprobantes({required this.venta, required this.negocio, required this.cliente});
  final Venta venta;
  final Negocio negocio;
  final Cliente? cliente;

  @override
  State<_Comprobantes> createState() => _ComprobantesState();
}

class _ComprobantesState extends State<_Comprobantes> {
  late _Doc _doc = widget.venta.factura != null ? _Doc.factura : _Doc.notaVenta;
  bool _dosCopias = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.venta;
    final n = widget.negocio;
    final esFactura = _doc == _Doc.factura;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (v.factura != null) ...[
        SegmentedButton<_Doc>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Doc.factura, label: Text('Factura'), icon: Icon(Icons.receipt_long_outlined)),
            ButtonSegment(value: _Doc.notaVenta, label: Text('Nota de venta'), icon: Icon(Icons.description_outlined)),
          ],
          selected: {_doc},
          onSelectionChanged: (s) => setState(() => _doc = s.first),
        ),
        const SizedBox(height: 8),
      ],
      Card(
        child: SwitchListTile(
          value: _dosCopias,
          onChanged: (x) => setState(() => _dosCopias = x),
          title: const Text('Dos copias'),
          subtitle: Text(!_dosCopias
              ? 'Una para el comprador y otra para vos'
              : esFactura
                  ? 'Se imprimen dos facturas, una en cada hoja'
                  : 'Se imprimen dos notas de venta, una en cada hoja'),
        ),
      ),
      const SizedBox(height: 10),
      DocActions(
        // Si cambia lo elegido, se genera de nuevo.
        key: ValueKey('$_doc-$_dosCopias'),
        build: () => esFactura ? pdfFactura(v, n, duplicado: _dosCopias) : pdfNotaVenta(v, n, duplicado: _dosCopias),
        fileName: esFactura ? archivoFactura(v, duplicado: _dosCopias) : archivoVenta(v, duplicado: _dosCopias),
        shareText: mensajeVenta(v, n.nombre),
        telefono: widget.cliente?.telefono,
        destinatario: widget.cliente?.contacto ?? v.cliente.nombre,
      ),
    ]);
  }
}
