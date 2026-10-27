import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sincronizacion_provider.dart';
import '../theme/app_theme.dart';

String _pendientes(int n) => n == 1 ? '1 pendiente sin sincronizar' : '$n pendientes sin sincronizar';

/// Franja sobre la barra de abajo: solo aparece sin señal o con algo sin subir.
class FranjaSincronizacion extends StatelessWidget {
  const FranjaSincronizacion({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SincronizacionProvider>();
    if (s.enLinea && s.pendientes == 0) return const SizedBox.shrink();
    final (texto, color, fondo, icono) = s.conError > 0
        ? ('${s.conError == 1 ? '1 pedido no se pudo subir' : '${s.conError} no se pudieron subir'}: tocá para ver', AppColors.red, AppColors.redSoft, Icons.error_outline)
        : !s.enLinea
            ? ('Sin señal${s.pendientes > 0 ? ' · ${_pendientes(s.pendientes)}' : ': los pedidos se guardan en el teléfono'}', AppColors.orange, AppColors.orangeSoft, Icons.cloud_off_outlined)
            : (s.sincronizando ? 'Sincronizando…' : _pendientes(s.pendientes), AppColors.blue, AppColors.blueSoft, Icons.cloud_upload_outlined);
    return Material(
      color: fondo,
      child: InkWell(
        onTap: s.sincronizar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(icono, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13))),
            if (s.sincronizando)
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
            else if (s.pendientes > 0)
              Text('Reintentar', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}

/// Estado en la lista de pedidos: también dice cuando está todo sincronizado.
class EstadoSincronizacion extends StatelessWidget {
  const EstadoSincronizacion({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SincronizacionProvider>();
    final (texto, color, icono) = s.conError > 0
        ? ('Hay pedidos que no se pudieron subir: abrilos para ver por qué', AppColors.red, Icons.error_outline)
        : s.pendientes > 0
            ? ('${_pendientes(s.pendientes)}${s.enLinea ? '' : ' · se suben solos al volver la señal'}', AppColors.orange, Icons.cloud_upload_outlined)
            : !s.enLinea
                ? ('Sin señal: los pedidos nuevos se guardan en el teléfono', AppColors.orange, Icons.cloud_off_outlined)
                : ('Todo sincronizado', AppColors.green, Icons.cloud_done_outlined);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icono, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5))),
      ]),
    );
  }
}
