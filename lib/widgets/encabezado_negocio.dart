import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/negocio_provider.dart';

/// Encabezado del negocio igual al de la factura: el nombre (la última palabra
/// en negrita), subrayado, "de" y el propietario, las actividades, la dirección
/// y el teléfono con la ciudad.
class EncabezadoNegocio extends StatelessWidget {
  const EncabezadoNegocio({super.key, this.size = 56, this.color = Colors.white, this.soloNombre = false});

  /// Alto de la letra del nombre; el resto se ajusta a esta medida.
  final double size;
  final Color color;

  /// Solo el nombre subrayado (sin propietario, actividades ni dirección).
  final bool soloNombre;

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<NegocioProvider>();
    final n = prov.negocio;
    final logo = n.logo;
    final palabras = n.nombre.trim().split(RegExp(r'\s+'));
    final ultima = palabras.length > 1 ? palabras.removeLast() : '';
    final primera = palabras.join(' ');
    final suave = color.withValues(alpha: 0.85);
    final contacto = [if (n.telefono != null) 'Cel.: ${n.telefono}', ?n.ciudad, 'Paraguay'].join('  -  ');

    // Hasta saber el nombre de verdad no se muestra (ocupa su lugar igual).
    return AnimatedOpacity(
      opacity: prov.listo ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.2),
              child: Image.memory(logo, height: size * 1.3, fit: BoxFit.contain),
            ),
            SizedBox(height: size * 0.25),
          ],
          // Nombre subrayado, como en el talonario.
          Container(
            padding: EdgeInsets.only(bottom: size * 0.06),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: color, width: size * 0.045),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: size * 0.2,
              children: [
                Text(
                  primera,
                  style: TextStyle(fontFamily: 'DMSerif', fontSize: size * 0.8, height: 1.05, color: color),
                ),
                if (ultima.isNotEmpty)
                  Text(
                    ultima,
                    style: TextStyle(fontSize: size, height: 1.0, fontWeight: FontWeight.w800, color: color),
                  ),
              ],
            ),
          ),
          if (soloNombre)
            const SizedBox.shrink()
          else ...[
            if (n.propietario != null) ...[
              SizedBox(height: size * 0.12),
              Text(
                'de ${n.propietario}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: size * 0.27, fontStyle: FontStyle.italic, color: suave),
              ),
            ],
            if (n.actividades != null) ...[
              SizedBox(height: size * 0.22),
              Text(
                n.actividades!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: size * 0.28, height: 1.35, fontWeight: FontWeight.w500, color: color),
              ),
            ],
            SizedBox(height: size * 0.22),
            if (n.direccion != null)
              Text(
                n.direccion!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: size * 0.28, color: suave),
              ),
            Text(
              contacto,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: size * 0.28, color: suave),
            ),
          ],
        ],
      ),
    );
  }
}
