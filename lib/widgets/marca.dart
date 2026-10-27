import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/negocio_provider.dart';
import '../theme/app_theme.dart';

/// Logo (si hay) y nombre del negocio.
class Marca extends StatelessWidget {
  const Marca({super.key, this.size = 40, this.color = AppColors.ink, this.mostrarRubro = false});
  final double size;
  final Color color;
  final bool mostrarRubro;

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<NegocioProvider>();
    final n = prov.negocio;
    final logo = n.logo;
    // Hasta saber el nombre de verdad no se muestra (ocupa su lugar igual).
    return AnimatedOpacity(
      opacity: prov.listo ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.2),
              child: Image.memory(logo, width: size * 1.2, height: size * 1.2, fit: BoxFit.cover),
            ),
            SizedBox(width: size * 0.3),
          ],
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mostrarRubro)
                  Text(
                    n.rubro.toUpperCase(),
                    style: TextStyle(fontSize: size * 0.3, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.accent),
                  ),
                Text(
                  n.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'DMSerif', fontSize: size * 0.7, height: 1.05, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
