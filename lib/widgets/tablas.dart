import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

const estiloEncabezadoTabla = TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13);
const estiloNumerosTabla = TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 14);
const fondoEncabezadoTabla = WidgetStatePropertyAll(Color(0xFFF0F3F8));

/// Tabla con scroll horizontal (en el celular se desliza de costado, nada queda
/// apretado). En pantallas anchas ocupa todo el ancho.
Widget tablaDeslizable(Widget tabla) => Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth), child: tabla),
        ),
      ),
    );

/// Etiqueta de estado con color (Disponible, Por agotarse, Agotado...).
class EtiquetaEstado extends StatelessWidget {
  const EtiquetaEstado(this.texto, this.color, this.fondo, {super.key});
  final String texto;
  final Color color;
  final Color fondo;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

/// Fecha corta para tablas: 16/10/26.
String fechaTabla(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';
