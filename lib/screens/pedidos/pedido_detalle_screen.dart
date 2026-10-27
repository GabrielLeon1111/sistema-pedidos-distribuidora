import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/cliente.dart';
import '../../models/linea.dart';
import '../../models/negocio.dart';
import '../../models/pago.dart';
import '../../models/pedido.dart';
import '../../providers/auth_provider.dart';
import '../../providers/negocio_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../providers/sincronizacion_provider.dart';
import '../../repositories/cliente_repository.dart';
import '../../repositories/pedido_repository.dart';
import '../../repositories/venta_repository.dart';
import '../../services/mensajes.dart';
import '../../services/pdf_documentos.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/doc_actions.dart';
import '../../widgets/estados.dart';
import '../../widgets/reloading_future.dart';
import '../cobros/pago_sheet.dart';
import '../proveedor/consolidado_screen.dart';
import '../ventas/venta_screen.dart';
import 'entrega_screen.dart';
import 'pedido_editor_screen.dart';
import 'recibir_pedido_screen.dart';

/// Detalle de una nota de pedido: estado de cada producto, confirmación de
/// parciales, señas, entrega y la nota en PDF o imagen.
class PedidoDetalleScreen extends StatelessWidget {
  const PedidoDetalleScreen({super.key, required this.id});
  final String id;

  Future<(Pedido, List<Pago>, Cliente?)> _cargar(BuildContext context) async {
    final repo = context.read<PedidoRepository>();
    final clientes = context.read<ClienteRepository>();
    final p = await repo.obtener(id);
    final senas = await repo.senas(id);
    final c = await clientes.obtener(p.clienteId);
    return (p, senas, c);
  }

  @override
  Widget build(BuildContext context) => ReloadingFuture<(Pedido, List<Pago>, Cliente?)>(
        titulo: 'Nota de pedido',
        contexto: 'pedido',
        load: () => _cargar(context),
        builder: (context, d, reload) => _Detalle(pedido: d.$1, senas: d.$2, cliente: d.$3),
      );
}

class _Detalle extends StatelessWidget {
  const _Detalle({required this.pedido, required this.senas, required this.cliente});
  final Pedido pedido;
  final List<Pago> senas;
  final Cliente? cliente;

  int get _sena => senas.fold(0, (s, p) => s + p.aFavor);

  /// [f] recibe la clave contra duplicados de esta acción (una por cada vez
  /// que se confirma el diálogo).
  Future<void> _accion(BuildContext context, String contexto, Future<void> Function(String clave) f, {String? ok}) async {
    final clave = nuevaClave();
    final hecho = await runSafe(context, contexto, () => f(clave), ok: ok);
    if (hecho && context.mounted) context.read<RefreshBus>().changed();
  }

  Future<void> _descartar(BuildContext context) async {
    final ok = await confirmar(
      context,
      titulo: '¿Descartar la nota N° ${nroDoc(pedido.numero)}?',
      mensaje: 'Todavía no se subió: se borra de este teléfono y no queda en ningún lado.',
      si: 'Descartar',
      peligro: true,
    );
    if (!ok || !context.mounted) return;
    await context.read<PedidoRepository>().descartarPendiente(pedido.id);
    if (!context.mounted) return;
    context.read<RefreshBus>().changed();
    context.read<SincronizacionProvider>().recontar();
    Navigator.pop(context);
  }

  Future<void> _anular(BuildContext context) async {
    final m = await pedirMotivo(context,
        titulo: 'Anular pedido N° ${nroDoc(pedido.numero)}',
        ayuda: pedido.estado == EstadoPedido.cargado ? null : 'Lo que ya llegó entra al stock con lo que se pagó.');
    if (m == null || !context.mounted) return;
    await _accion(context, 'anularPedido', (c) => context.read<PedidoRepository>().anular(pedido.id, m, clave: c), ok: 'Pedido anulado');
  }

  Future<void> _noEstaba(BuildContext context) async {
    final f = await elegirFecha(context, inicial: DateTime.now().add(const Duration(days: 1)), primera: DateTime.now());
    if (f == null || !context.mounted) return;
    await _accion(context, 'noEstaba', (c) => context.read<VentaRepository>().noEstaba(pedido.id, f, clave: c),
        ok: 'Queda pendiente para el ${fechaCorta.format(f)}');
  }

  Future<void> _rechazar(BuildContext context) async {
    final m = await pedirMotivo(context,
        titulo: 'El local no recibió el pedido',
        ayuda: 'Queda rechazado con el motivo y la mercadería entra al stock.',
        boton: 'Rechazado');
    if (m == null || !context.mounted) return;
    await _accion(context, 'rechazar', (c) => context.read<VentaRepository>().rechazar(pedido.id, m, clave: c), ok: 'Pedido rechazado');
  }

  Future<void> _confirmar(BuildContext context, Linea l, bool acepta) async {
    final ok = await confirmar(
      context,
      titulo: acepta ? '¿El local acepta?' : '¿El local no acepta?',
      mensaje: acepta
          ? 'Se le entregan ${cantidad(l.cantidadEfectiva)} de ${cantidad(l.cantidad)} ${l.unidadTexto()} de ${l.descripcion}. La nota se ajusta para reenviarla.'
          : 'Se anula ${l.descripcion} en este pedido y lo que llegó (${cantidad(l.cantidadEfectiva)}) entra al stock.',
      si: acepta ? 'Acepta' : 'No acepta',
      peligro: !acepta,
    );
    if (!ok || !context.mounted) return;
    await _accion(context, 'confirmarParcial', (c) => context.read<PedidoRepository>().confirmarParcial(pedido.id, l.id, acepta: acepta, clave: c));
  }

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final esAdmin = context.select<AuthProvider, bool>((a) => a.esAdmin);
    final negocio = context.watch<NegocioProvider>().negocio;
    final abierto = !p.cerrado;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido N° ${nroDoc(p.numero)}'),
        actions: [
          if (p.editable)
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoEditorScreen(pedido: p))),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 40),
        children: [
          if (p.sinSincronizar)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Aviso(
                p.errorSincronizacion != null
                    ? 'No se pudo subir: ${p.errorSincronizacion} Editala para corregirla, o descartala.'
                    : 'Guardada en el teléfono: se sube sola cuando haya señal. El número ya es definitivo.',
                icon: p.errorSincronizacion != null ? Icons.error_outline : Icons.cloud_upload_outlined,
                color: p.errorSincronizacion != null ? AppColors.red : AppColors.orange,
                fondo: p.errorSincronizacion != null ? AppColors.redSoft : AppColors.orangeSoft,
              ),
            ),
          ..._contenido(context, p, esAdmin, negocio, abierto),
        ],
      ),
    );
  }

  List<Widget> _contenido(BuildContext context, Pedido p, bool esAdmin, Negocio negocio, bool abierto) => [
          Cuerpo(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(p.cliente.nombre, style: Theme.of(context).textTheme.titleLarge)),
                      PillPedido(p),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      [
                        fechaHora.format(p.fecha),
                        if (p.vendedorNombre != null) 'Levantó: ${p.vendedorNombre}',
                        if (p.fechaEntrega != null) 'Entrega: ${fechaCorta.format(p.fechaEntrega!)}',
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    if (p.cliente.razonSocial != null || p.cliente.ruc != null)
                      Text([p.cliente.razonSocial, if (p.cliente.ruc != null) 'RUC ${p.cliente.ruc}'].whereType<String>().join(' · '),
                          style: const TextStyle(color: AppColors.muted)),
                    if (p.motivo != null) ...[
                      const SizedBox(height: 8),
                      Aviso('Motivo: ${p.motivo}', icon: Icons.info_outline, color: AppColors.red, fondo: AppColors.redSoft),
                    ],
                  ]),
                ),
              ),
              if (p.esperandoConfirmacion && abierto) ...[
                const SizedBox(height: 10),
                const Aviso(
                  'Llegó una parte de algunos productos: preguntale al local si acepta la cantidad menor.',
                  icon: Icons.hourglass_top_rounded,
                ),
              ],
              SectionTitle('Productos (${p.lineas.length})'),
              Card(
                child: Column(children: [
                  for (var i = 0; i < p.lineas.length; i++) ...[
                    if (i > 0) const Divider(),
                    _LineaPedido(
                      l: p.lineas[i],
                      esAdmin: esAdmin,
                      mostrarEstado: p.estado != EstadoPedido.cargado,
                      onConfirmar: abierto && p.lineas[i].esperandoConfirmacion ? (acepta) => _confirmar(context, p.lineas[i], acepta) : null,
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 10),
              TotalDestacado(
                etiqueta: 'TOTAL',
                monto: p.total,
                detalle: p.total != p.totalPedido ? 'Pedido original: ${gs(p.totalPedido)}' : null,
              ),

              if (senas.isNotEmpty) ...[
                const SectionTitle('Señas y adelantos'),
                Card(
                  child: Column(children: [
                    for (final s in senas)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.savings_outlined),
                        title: Text('${gs(s.monto)} · ${metodoPagoTexto(s.metodo)}'),
                        subtitle: Text('Recibo N° ${nroDoc(s.numero)} · ${fechaCorta.format(s.fecha)}'),
                      ),
                  ]),
                ),
              ],
              if (p.observaciones != null) ...[
                const SectionTitle('Observaciones'),
                Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(p.observaciones!))),
              ],
              // ---------- Acciones ----------
              if (abierto && esAdmin && !p.sinSincronizar) ...[
                const SectionTitle('Entrega y cobro'),
                if (p.entregable)
                  FilledButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntregaScreen(pedido: p, sena: _sena))),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Entregar y facturar'),
                  )
                else if (p.estado == EstadoPedido.cargado) ...[
                  // Convertir la nota en venta: llegó la mercadería (sin hoja del proveedor).
                  FilledButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecibirPedidoScreen(pedido: p, sena: _sena))),
                    icon: const Icon(Icons.point_of_sale),
                    label: const Text('Ya llegó la mercadería: pasar a venta'),
                  ),
                  const SizedBox(height: 4),
                  const Text('O pedila al proveedor desde la pestaña Proveedor.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ] else if (p.estado == EstadoPedido.pedido) ...[
                  FilledButton.icon(
                    onPressed: p.consolidadoId == null
                        ? null
                        : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConsolidadoScreen(id: p.consolidadoId!))),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Llegó la mercadería: registrar recepción'),
                  ),
                  const SizedBox(height: 4),
                  const Text('Está en una hoja del proveedor: al registrar la recepción queda lista para pasar a venta.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ],
                if (p.entregable || p.esperandoConfirmacion) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(onPressed: () => _noEstaba(context), icon: const Icon(Icons.event_repeat), label: const Text('No estaba')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                        onPressed: () => _rechazar(context),
                        icon: const Icon(Icons.do_not_disturb_alt),
                        label: const Text('No recibió'),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => registrarPago(
                    context,
                    clienteId: p.clienteId,
                    clienteNombre: p.cliente.nombre,
                    maximo: (p.total - _sena).clamp(0, p.total),
                    pedidoId: p.id,
                  ),
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('Registrar seña o adelanto'),
                ),
              ],
              if (p.estado == EstadoPedido.entregado && p.ventaId != null && esAdmin) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VentaScreen(id: p.ventaId!))),
                  icon: const Icon(Icons.receipt_outlined),
                  label: const Text('Ver factura'),
                ),
              ],
              const SectionTitle('Nota de pedido'),
              DocActions(
                build: () => pdfNotaPedido(esAdmin ? p : p.sinCostos(), negocio, sena: _sena),
                fileName: archivoPedido(p),
                shareText: mensajePedido(p, negocio.nombre),
                telefono: cliente?.telefono,
                destinatario: cliente?.contacto ?? p.cliente.nombre,
              ),
              if (p.sinSincronizar) ...[
                const SizedBox(height: 20),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  onPressed: () => _descartar(context),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Descartar nota (todavía no se subió)'),
                ),
              ] else if (abierto && (p.estado == EstadoPedido.cargado || esAdmin)) ...[
                const SizedBox(height: 20),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  onPressed: () => _anular(context),
                  icon: const Icon(Icons.block),
                  label: const Text('Anular pedido'),
                ),
              ],
            ]),
          ),
        ];
}

class _LineaPedido extends StatelessWidget {
  const _LineaPedido({required this.l, required this.esAdmin, required this.mostrarEstado, this.onConfirmar});
  final Linea l;
  final bool esAdmin;
  final bool mostrarEstado;
  final void Function(bool acepta)? onConfirmar;

  @override
  Widget build(BuildContext context) {
    final detalle = [
      '${cantidad(l.cantidadEfectiva)}${l.cambioCantidad ? ' de ${cantidad(l.cantidad)}' : ''} ${l.unidadTexto()} × ${gs(l.precio)}',
      ?l.textoDescuento,
      if (l.codigo != null) 'Cód. ${l.codigo}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(
              l.descripcion,
              style: TextStyle(fontWeight: FontWeight.w700, decoration: l.anulada ? TextDecoration.lineThrough : null),
            ),
          ),
          Text(gs(l.total), style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 2),
        Text(detalle.join(' · '), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        if (l.nota != null) ...[
          const SizedBox(height: 2),
          Text('Detalle: ${l.nota}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
        if (mostrarEstado || l.deStock) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (mostrarEstado && !l.deStock) Pill(l.estado.texto, color: colorLinea(l.estado)),
            if (l.deStock) const Pill('Del stock', color: AppColors.blue),
            if (l.esperandoConfirmacion) const Pill('Esperando confirmación', color: AppColors.orange),
            if (l.confirmacion == 'aceptada') const Pill('El local aceptó', color: AppColors.green),
          ]),
        ],
        if (onConfirmar != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size(0, 42)),
                onPressed: () => onConfirmar!(true),
                child: const Text('Acepta'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red), minimumSize: const Size(0, 42)),
                onPressed: () => onConfirmar!(false),
                child: const Text('No acepta'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
