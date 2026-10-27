import 'package:flutter/material.dart';
import '../utils/formato.dart';

enum TipoPeriodo { dia, semana, mes, rango }

/// Un período de fechas (día, semana, mes o rango elegido).
class PeriodoElegido {
  const PeriodoElegido(this.tipo, this.desde, this.hasta);
  final TipoPeriodo tipo;
  final DateTime desde;
  final DateTime hasta;

  factory PeriodoElegido.de(TipoPeriodo t, [DateTime? ref]) {
    final hoy = inicioDia(ref ?? DateTime.now());
    return switch (t) {
      TipoPeriodo.dia => PeriodoElegido(t, hoy, hoy),
      TipoPeriodo.semana => PeriodoElegido(t, hoy.subtract(Duration(days: hoy.weekday - 1)), hoy),
      TipoPeriodo.mes => PeriodoElegido(t, DateTime(hoy.year, hoy.month), hoy),
      TipoPeriodo.rango => PeriodoElegido(t, hoy.subtract(const Duration(days: 30)), hoy),
    };
  }

  String get texto => desde == hasta ? fechaCorta.format(desde) : '${fechaCorta.format(desde)} al ${fechaCorta.format(hasta)}';
}

/// Botones Hoy / Semana / Mes / Rango.
class SelectorPeriodo extends StatelessWidget {
  const SelectorPeriodo({super.key, required this.valor, required this.onChanged});
  final PeriodoElegido valor;
  final ValueChanged<PeriodoElegido> onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<TipoPeriodo>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: TipoPeriodo.dia, label: Text('Hoy')),
            ButtonSegment(value: TipoPeriodo.semana, label: Text('Semana')),
            ButtonSegment(value: TipoPeriodo.mes, label: Text('Mes')),
            ButtonSegment(value: TipoPeriodo.rango, label: Text('Rango')),
          ],
          selected: {valor.tipo},
          onSelectionChanged: (v) async {
            if (v.first != TipoPeriodo.rango) return onChanged(PeriodoElegido.de(v.first));
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime.now(),
              initialDateRange: DateTimeRange(start: valor.desde, end: valor.hasta),
              locale: const Locale('es'),
            );
            if (r != null) onChanged(PeriodoElegido(TipoPeriodo.rango, inicioDia(r.start), inicioDia(r.end)));
          },
        ),
        const SizedBox(height: 6),
        Text(valor.texto, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);
}
