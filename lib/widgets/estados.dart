import 'package:flutter/material.dart';
import '../models/consolidado.dart';
import '../models/linea.dart';
import '../models/pedido.dart';
import '../models/venta.dart';
import '../theme/app_theme.dart';
import 'common.dart';

Color colorPedido(EstadoPedido e) => switch (e) {
      EstadoPedido.cargado => AppColors.blue,
      EstadoPedido.pedido => AppColors.orange,
      EstadoPedido.recibido => AppColors.primary,
      EstadoPedido.pendiente => AppColors.orange,
      EstadoPedido.entregado => AppColors.green,
      EstadoPedido.rechazado => AppColors.red,
      EstadoPedido.anulado => AppColors.muted,
    };

class PillPedido extends StatelessWidget {
  const PillPedido(this.p, {super.key});
  final Pedido p;

  @override
  Widget build(BuildContext context) {
    if (p.esperandoConfirmacion && !p.cerrado) return const Pill('Esperando confirmación', color: AppColors.orange);
    return Pill(p.estado.texto, color: colorPedido(p.estado));
  }
}

class PillPago extends StatelessWidget {
  const PillPago(this.e, {super.key});
  final EstadoPago e;

  @override
  Widget build(BuildContext context) => Pill(e.texto,
      color: switch (e) {
        EstadoPago.pagado => AppColors.green,
        EstadoPago.parcial => AppColors.orange,
        EstadoPago.fiado => AppColors.red,
        EstadoPago.anulada => AppColors.muted,
      });
}

Color colorLinea(EstadoLinea e) => switch (e) {
      EstadoLinea.pendiente => AppColors.muted,
      EstadoLinea.llego => AppColors.green,
      EstadoLinea.parcial => AppColors.orange,
      EstadoLinea.noLlego || EstadoLinea.rechazada => AppColors.red,
    };

Color colorRecepcion(EstadoRecepcion e) => switch (e) {
      EstadoRecepcion.pendiente => AppColors.muted,
      EstadoRecepcion.completo => AppColors.green,
      EstadoRecepcion.parcial => AppColors.orange,
      EstadoRecepcion.noLlego => AppColors.red,
    };
