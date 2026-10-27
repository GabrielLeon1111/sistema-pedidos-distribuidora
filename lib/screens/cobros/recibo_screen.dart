import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/cliente.dart';
import '../../models/pago.dart';
import '../../providers/negocio_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/cliente_repository.dart';
import '../../repositories/cobro_repository.dart';
import '../../services/mensajes.dart';
import '../../services/pdf_documentos.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/doc_actions.dart';
import '../../widgets/reloading_future.dart';

/// Recibo de pago: PDF o imagen, y anulación con motivo.
class ReciboScreen extends StatelessWidget {
  const ReciboScreen({super.key, required this.id});
  final String id;

  Future<(Pago, int, Cliente?)> _cargar(BuildContext context) async {
    final cobros = context.read<CobroRepository>();
    final clientes = context.read<ClienteRepository>();
    final p = await cobros.obtener(id);
    final cuenta = await cobros.cuenta(p.clienteId);
    final c = await clientes.obtener(p.clienteId);
    return (p, cuenta.deuda, c);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Recibo')),
        body: ReloadingFuture<(Pago, int, Cliente?)>(
          contexto: 'recibo',
          load: () => _cargar(context),
          builder: (context, d, reload) {
            final (p, saldo, cliente) = d;
            final negocio = context.watch<NegocioProvider>().negocio;
            return ListView(
              padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 32),
              children: [
                Cuerpo(
                  maxWidth: 640,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('Recibo N° ${nroDoc(p.numero)}', style: Theme.of(context).textTheme.titleLarge)),
                            if (p.anulado) const Pill('Anulado', color: AppColors.red),
                            if (p.esSena && !p.anulado) const Pill('Seña', color: AppColors.blue),
                          ]),
                          const SizedBox(height: 4),
                          Text(p.clienteNombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 10),
                          KeyValueRow('Monto', gs(p.monto), bold: true, big: true),
                          KeyValueRow('Forma de pago', metodoPagoTexto(p.metodo)),
                          KeyValueRow('Fecha', fechaHora.format(p.fecha)),
                          if (p.registradoPor != null) KeyValueRow('Registró', p.registradoPor!),
                          for (final a in p.aplicaciones) KeyValueRow('Nota de venta N° ${nroDoc(a.ventaNumero)}', gs(a.monto)),
                          if (p.aFavor > 0) KeyValueRow(p.esSena ? 'Seña sin aplicar' : 'A favor del local', gs(p.aFavor), valueColor: AppColors.blue),
                          if (!p.anulado) KeyValueRow('Saldo del local', gs(saldo), valueColor: saldo > 0 ? AppColors.red : AppColors.green),
                          if (p.nota != null) KeyValueRow('Nota', p.nota!),
                          if (p.anulado) KeyValueRow('Motivo de anulación', p.motivoAnulacion ?? '—', valueColor: AppColors.red),
                        ]),
                      ),
                    ),
                    const SectionTitle('Recibo en PDF o imagen'),
                    DocActions(
                      build: () => pdfRecibo(p, negocio, saldoRestante: saldo),
                      fileName: archivoRecibo(p),
                      shareText: mensajeRecibo(p, negocio.nombre, saldo: saldo),
                      telefono: cliente?.telefono,
                      destinatario: cliente?.contacto ?? p.clienteNombre,
                    ),
                    if (!p.anulado) ...[
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                        onPressed: () async {
                          final m = await pedirMotivo(context, titulo: 'Anular recibo N° ${nroDoc(p.numero)}', ayuda: 'El pago deja de descontar de la deuda.');
                          if (m == null || !context.mounted) return;
                          final ok = await runSafe(context, 'anularPago', () => context.read<CobroRepository>().anular(p.id, m, clave: nuevaClave()), ok: 'Recibo anulado');
                          if (ok && context.mounted) context.read<RefreshBus>().changed();
                        },
                        icon: const Icon(Icons.block),
                        label: const Text('Anular pago'),
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
