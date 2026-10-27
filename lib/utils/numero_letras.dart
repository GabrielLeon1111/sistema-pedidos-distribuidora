// Número a letras para el "Total a pagar" de la factura: 44750 -> "cuarenta y cuatro mil setecientos cincuenta".

const _unidades = [
  '', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve',
  'diez', 'once', 'doce', 'trece', 'catorce', 'quince', 'dieciséis', 'diecisiete', 'dieciocho', 'diecinueve',
  'veinte', 'veintiuno', 'veintidós', 'veintitrés', 'veinticuatro', 'veinticinco', 'veintiséis', 'veintisiete', 'veintiocho', 'veintinueve',
];
const _decenas = ['', '', '', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa'];
const _centenas = ['', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos', 'seiscientos', 'setecientos', 'ochocientos', 'novecientos'];

String _menorDeMil(int n) {
  if (n == 0) return '';
  if (n == 100) return 'cien';
  final c = n ~/ 100;
  final r = n % 100;
  final partes = <String>[
    if (c > 0) _centenas[c],
    if (r > 0 && r < 30) _unidades[r],
    if (r >= 30) r % 10 == 0 ? _decenas[r ~/ 10] : '${_decenas[r ~/ 10]} y ${_unidades[r % 10]}',
  ];
  return partes.join(' ');
}

/// "uno" pasa a "un" delante de "mil" y "millones" (un mil no: "mil"; veintiún mil).
String _apocope(String s) => s.endsWith('veintiuno')
    ? '${s.substring(0, s.length - 9)}veintiún'
    : s.endsWith('uno')
        ? '${s.substring(0, s.length - 3)}un'
        : s;

String numeroALetras(int numero) {
  if (numero == 0) return 'cero';
  if (numero < 0) return 'menos ${numeroALetras(-numero)}';
  final millones = numero ~/ 1000000;
  final miles = (numero % 1000000) ~/ 1000;
  final resto = numero % 1000;
  final partes = <String>[];
  if (millones > 0) {
    partes.add(millones == 1 ? 'un millón' : '${_apocope(_conMiles(millones))} millones');
  }
  if (miles > 0) partes.add(miles == 1 ? 'mil' : '${_apocope(_menorDeMil(miles))} mil');
  if (resto > 0) partes.add(_menorDeMil(resto));
  return partes.join(' ');
}

String _conMiles(int n) {
  final m = n ~/ 1000;
  final r = n % 1000;
  return [if (m > 0) (m == 1 ? 'mil' : '${_apocope(_menorDeMil(m))} mil'), if (r > 0) _menorDeMil(r)].join(' ');
}
