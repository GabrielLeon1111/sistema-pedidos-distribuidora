import 'package:intl/intl.dart';

final _gs = NumberFormat.decimalPattern('es');
final fechaCorta = DateFormat('dd/MM/yyyy', 'es');
final fechaHora = DateFormat('dd/MM/yyyy HH:mm', 'es');
final hora = DateFormat('HH:mm', 'es');
final fechaLarga = DateFormat("EEEE d 'de' MMMM", 'es');
final mesAnio = DateFormat('MMMM yyyy', 'es');
final mesCorto = DateFormat('MMM', 'es');

/// 1355000 -> "1.355.000"
String miles(num valor) => _gs.format(valor.round());

/// 1355000 -> "Gs. 1.355.000"
String gs(num valor) => 'Gs. ${miles(valor)}';

/// Número de documento con ceros: 12 -> "000012"
String nroDoc(int n) => n.toString().padLeft(6, '0');

/// Cantidad legible: 3 -> "3", 2.5 -> "2,5", 3000 -> "3.000".
String cantidad(num valor) {
  final v = valor.toDouble();
  if (v == v.roundToDouble()) return miles(v);
  return NumberFormat('#,##0.###', 'es').format(v);
}

/// Interpreta lo que escribe el usuario: "2,5", "2.5", "3.000", "1/2".
/// Devuelve null si no se entiende.
double? leerCantidad(String texto) {
  final t = texto.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return null;
  final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(t);
  if (frac != null) {
    final den = int.parse(frac.group(2)!);
    if (den == 0) return null;
    return double.parse((int.parse(frac.group(1)!) / den).toStringAsFixed(3));
  }
  // "2,5" → 2.5 · "3.000" (punto de miles) → 3000 · "2.5" → 2.5
  final String normal;
  if (t.contains(',')) {
    normal = t.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    normal = t.replaceAll('.', '');
  } else {
    normal = t;
  }
  final v = double.tryParse(normal);
  if (v == null || v.isNaN || v.isInfinite) return null;
  return double.parse(v.toStringAsFixed(3));
}

/// "1.355.000" o "1355000" -> 1355000
int? leerMonto(String texto) {
  final limpio = texto.replaceAll(RegExp(r'[^0-9]'), '');
  if (limpio.isEmpty) return null;
  return int.tryParse(limpio);
}

/// Etiqueta de la unidad según la cantidad: (2, 'caja') -> 'cajas'.
String unidadPlural(String unidad, num cant) {
  if (cant <= 1) return unidad;
  const especiales = {'unidad': 'unidades', 'kg': 'kg', 'lt': 'lt', 'm': 'm', 'docena': 'docenas', 'pack': 'packs', 'par': 'pares'};
  return especiales[unidad] ?? (unidad.endsWith('s') ? unidad : '${unidad}s');
}

/// "docenas", "paquete de 12", "paquetes de 12".
String textoForma(String unidad, double factor, num cant) {
  final base = unidadPlural(unidad, cant);
  if (factor <= 1 || unidad == 'docena') return base;
  return '$base de ${cantidad(factor)}';
}

String metodoPagoTexto(String m) => switch (m) {
      'efectivo' => 'Efectivo',
      'transferencia' => 'Transferencia',
      'qr' => 'QR',
      _ => m,
    };

/// Margen sobre lo que se pagó: compra 50.000 y venta 60.000 -> 20 %.
/// null si no hay precio de compra.
double? margenPct(int precioVenta, int precioCompra) {
  if (precioCompra <= 0) return null;
  return (precioVenta - precioCompra) * 100 / precioCompra;
}

/// "20 % · Gs. 10.000"
String margenTexto(int precioVenta, int precioCompra) {
  final p = margenPct(precioVenta, precioCompra);
  if (p == null) return 'Sin precio de compra';
  return '${NumberFormat('#,##0.#', 'es').format(p)} % · ${gs(precioVenta - precioCompra)}';
}

/// Teléfono paraguayo a formato internacional para WhatsApp: 0981 123456 -> 595981123456
String? telefonoWhatsapp(String? tel) {
  if (tel == null) return null;
  var d = tel.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('595')) return d;
  if (d.startsWith('0')) d = d.substring(1);
  return '595$d';
}

/// Días desde [desde] hasta hoy (antigüedad de una deuda).
int diasDesde(DateTime desde) {
  final hoy = DateTime.now();
  final a = DateTime(desde.year, desde.month, desde.day);
  final b = DateTime(hoy.year, hoy.month, hoy.day);
  return b.difference(a).inDays;
}

String antiguedadTexto(int dias) => switch (dias) {
      0 => 'hoy',
      1 => 'hace 1 día',
      _ => 'hace $dias días',
    };

/// Inicio del día (00:00).
DateTime inicioDia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Fin del día (23:59:59.999).
DateTime finDia(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
