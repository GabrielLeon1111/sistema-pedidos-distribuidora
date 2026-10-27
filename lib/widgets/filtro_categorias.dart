import 'package:flutter/material.dart';

/// Fila de categorías para filtrar (Todas, Medicamentos, Calzados...).
/// [seleccion] null = todas.
class FiltroCategorias extends StatelessWidget {
  const FiltroCategorias({super.key, required this.categorias, required this.seleccion, required this.onChanged, this.padding = EdgeInsets.zero});
  final List<String> categorias;
  final String? seleccion;
  final ValueChanged<String?> onChanged;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (categorias.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        children: [
          for (final c in [null, ...categorias])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(c ?? 'Todas'), selected: seleccion == c, onSelected: (_) => onChanged(c)),
            ),
        ],
      ),
    );
  }
}

/// Las categorías de una lista, ordenadas; las que no tienen van como "Sin categoría".
const sinCategoria = 'Sin categoría';

List<String> categoriasDe(Iterable<String?> valores) => {for (final v in valores) v ?? sinCategoria}.toList()..sort();
