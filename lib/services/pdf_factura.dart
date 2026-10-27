import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/linea.dart';
import '../models/negocio.dart';
import '../models/venta.dart';
import '../utils/formato.dart';
import '../utils/numero_letras.dart';
import 'pdf_documentos.dart' show archivoVenta;
import 'pdf_fuentes.dart';

String archivoFactura(Venta v, {bool duplicado = false}) =>
    'Factura_${v.factura?.numeroCompleto.replaceAll(' ', '-') ?? nroDoc(v.numero)}_${v.cliente.nombre.trim().split(RegExp(r'\s+')).first}'
    '${duplicado ? '_2_copias' : ''}.pdf';

/// Montos de la factura por tasa de IVA (los precios ya incluyen el IVA).
class TotalesFactura {
  TotalesFactura(List<Linea> lineas) : exentas = _suma(lineas, 0), cinco = _suma(lineas, 5), diez = _suma(lineas, 10);

  final int exentas;
  final int cinco;
  final int diez;

  static int _suma(List<Linea> ls, int iva) => ls.where((l) => l.iva == iva).fold(0, (s, l) => s + l.total);

  int get total => exentas + cinco + diez;

  /// Liquidación del IVA: 5 % = total / 21 · 10 % = total / 11.
  int get iva5 => (cinco / 21).round();
  int get iva10 => (diez / 11).round();
  int get ivaTotal => iva5 + iva10;
}

const _negro = PdfColors.black;
const _filas = 12;


/// Recuadro del negocio como en el talonario: el nombre (la última palabra en
/// negrita), subrayado, el propietario, las actividades, la dirección y el teléfono.
/// Lo usan la factura, la nota de venta y la nota de pedido al proveedor.
pw.Widget encabezadoTalonario(Negocio n, PdfRecursos r) {
  pw.TextStyle t(double size, {pw.Font? font, double spacing = 0, pw.FontStyle? estilo}) =>
      pw.TextStyle(font: font ?? r.regular, fontSize: size, color: _negro, letterSpacing: spacing, fontStyle: estilo);
  const borde = pw.BorderSide(color: _negro, width: 0.9);
  final redondo = pw.BorderRadius.circular(8);
  final palabras = n.nombre.trim().split(RegExp(r'\s+'));
  final ultima = palabras.length > 1 ? palabras.removeLast() : '';
  final primera = palabras.join(' ');
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: pw.BoxDecoration(border: pw.Border.fromBorderSide(borde), borderRadius: redondo),
    child: pw.Column(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _negro, width: 1.4)),
          ),
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(primera, style: t(22, font: r.serif)),
              if (ultima.isNotEmpty) ...[pw.SizedBox(width: 6), pw.Text(ultima, style: t(28, font: r.black))],
            ],
          ),
        ),
        if (n.propietario != null) ...[pw.SizedBox(height: 2), pw.Text('de ${n.propietario}', style: t(8, estilo: pw.FontStyle.italic))],
        if (n.actividades != null) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            n.actividades!,
            textAlign: pw.TextAlign.center,
            style: t(8.5, font: r.medium),
          ),
        ],
        pw.SizedBox(height: 4),
        if (n.direccion != null) pw.Text(n.direccion!, textAlign: pw.TextAlign.center, style: t(9)),
        pw.Text([if (n.telefono != null) 'Cel.: ${n.telefono}', ?n.ciudad, 'Paraguay'].join('  -  '), textAlign: pw.TextAlign.center, style: t(9)),
      ],
    ),
  );
}

/// Factura igual al talonario del negocio.
/// Con [duplicado] sale dos veces, una en cada hoja (para el cliente y para el
/// archivo).
/// Con [nota] es la nota de venta: el mismo diseño, pero sin timbrado ni
/// vigencias, con el número de nota y sin valor fiscal.
Future<Uint8List> pdfFactura(Venta v, Negocio n, {bool duplicado = false, bool nota = false}) async {
  final r = await PdfRecursos.cargar();
  final f = v.factura;
  final tot = TotalesFactura(v.lineas);
  pw.TextStyle t(double size, {pw.Font? font, double spacing = 0, pw.FontStyle? estilo}) =>
      pw.TextStyle(font: font ?? r.regular, fontSize: size, color: _negro, letterSpacing: spacing, fontStyle: estilo);
  const borde = pw.BorderSide(color: _negro, width: 0.9);
  final redondo = pw.BorderRadius.circular(8);

  // ---------- Encabezado: negocio ----------
  final negocio = encabezadoTalonario(n, r);

  // ---------- Encabezado: timbrado ----------
  final timbrado = pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 8),
    decoration: pw.BoxDecoration(border: pw.Border.fromBorderSide(borde), borderRadius: redondo),
    child: pw.Column(
      children: nota
          ? [
              pw.SizedBox(height: 10),
              pw.Text('RUC: ${_rucConEspacios(n.ruc)}', style: t(11, font: r.medium)),
              pw.SizedBox(height: 6),
              pw.Text('NOTA DE VENTA', style: t(15, font: r.serif, spacing: 3)),
              pw.SizedBox(height: 4),
              pw.Text('N° ${nroDoc(v.numero)}', style: t(17, font: r.medium, spacing: 0.5)),
              pw.SizedBox(height: 10),
            ]
          : [
              pw.Text('TIMBRADO N° ${f?.timbrado ?? ''}', style: t(11, font: r.medium)),
              pw.Text('Fecha de Inicio de Vigencia ${f == null ? '' : fechaCorta.format(f.inicio)}', style: t(7.5)),
              pw.Text('Fecha de Fin de Vigencia ${f == null ? '' : fechaCorta.format(f.fin)}', style: t(7.5)),
              pw.Text('RUC: ${_rucConEspacios(n.ruc)}', style: t(11, font: r.medium)),
              pw.SizedBox(height: 2),
              pw.Text('FACTURA', style: t(15, font: r.serif, spacing: 4)),
              pw.SizedBox(height: 2),
              pw.Text(f?.numeroCompleto ?? '', style: t(17, font: r.medium, spacing: 0.5)),
            ],
    ),
  );

  // ---------- Datos del cliente ----------
  pw.Widget campo(String etiqueta, String? valor) => pw.Row(
    children: [
      pw.Text('$etiqueta ', style: t(8.5)),
      pw.Expanded(
        child: pw.Text(valor ?? '', style: t(9.5, font: r.medium), maxLines: 1),
      ),
    ],
  );
  pw.Widget casilla(bool marcada) => pw.Container(
    width: 11,
    height: 9,
    alignment: pw.Alignment.center,
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _negro, width: 0.8),
      borderRadius: pw.BorderRadius.circular(2),
    ),
    child: marcada ? pw.Text('X', style: t(7, font: r.black)) : null,
  );
  pw.Widget renglon(List<pw.Widget> hijos, {bool ultimo = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
    decoration: ultimo ? null : const pw.BoxDecoration(border: pw.Border(bottom: borde)),
    child: pw.Row(children: hijos),
  );
  final datos = pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.fromBorderSide(borde), borderRadius: redondo),
    child: pw.Column(
      children: [
        renglon([
          pw.Expanded(flex: 5, child: campo('Fecha de Emisión:', fechaCorta.format(v.fecha))),
          pw.Expanded(
            flex: 6,
            child: pw.Row(
              children: [
                pw.Text('Condición de Venta:  Contado ', style: t(8.5)),
                casilla(f?.contado ?? v.saldo == 0),
                pw.Spacer(),
                pw.Text('Crédito ', style: t(8.5)),
                casilla(!(f?.contado ?? v.saldo == 0)),
                pw.SizedBox(width: 10),
              ],
            ),
          ),
        ]),
        renglon([pw.Expanded(flex: 5, child: campo('R.U.C.:', v.cliente.ruc)), pw.Expanded(flex: 6, child: campo('Nota de Remisión N°:', f?.notaRemision))]),
        renglon([pw.Expanded(child: campo('Nombre o Razón Social:', v.cliente.razonSocial ?? v.cliente.nombre))]),
        renglon([
          pw.Expanded(flex: 7, child: campo('Dirección:', v.cliente.direccion)),
          pw.Expanded(flex: 4, child: campo('Tel.:', v.cliente.telefono)),
        ], ultimo: true),
      ],
    ),
  );

  // ---------- Detalle ----------
  // Producto | Descripción (detalle) | Cant. | Precio unitario | Exentas | 5% | 10%
  const anchos = [3.0, 2.3, 0.8, 1.35, 1.1, 1.1, 1.25];
  pw.Widget celda(String texto, int col, {bool derecha = true, bool centro = false, pw.Font? font, double size = 9, bool linea = true}) => pw.Expanded(
    flex: (anchos[col] * 100).round(),
    child: pw.Container(
      height: 17,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4),
      alignment: centro ? pw.Alignment.center : (derecha ? pw.Alignment.centerRight : pw.Alignment.centerLeft),
      decoration: pw.BoxDecoration(border: pw.Border(right: col < 6 ? borde : pw.BorderSide.none)),
      child: pw.Text(texto, style: t(size, font: font), maxLines: 1),
    ),
  );
  pw.Widget fila(List<String> c, {bool ultima = false}) => pw.Container(
    decoration: pw.BoxDecoration(
      border: ultima ? null : const pw.Border(bottom: pw.BorderSide(color: _negro, width: 0.4)),
    ),
    child: pw.Row(children: [
      celda(c[0], 0, derecha: false),
      celda(c[1], 1, derecha: false, size: 8),
      celda(c[2], 2, centro: true),
      celda(c[3], 3),
      celda(c[4], 4),
      celda(c[5], 5),
      celda(c[6], 6),
    ]),
  );

  final encabezadoTabla = pw.Container(
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: borde)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: (anchos[0] * 100).round(),
          child: pw.Container(
            height: 30,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(border: pw.Border(right: borde)),
            child: pw.Text('PRODUCTO', textAlign: pw.TextAlign.center, style: t(9, spacing: 2)),
          ),
        ),
        pw.Expanded(
          flex: (anchos[1] * 100).round(),
          child: pw.Container(
            height: 30,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(border: pw.Border(right: borde)),
            child: pw.Text('DESCRIPCIÓN', textAlign: pw.TextAlign.center, style: t(8.5, spacing: 1)),
          ),
        ),
        pw.Expanded(
          flex: (anchos[2] * 100).round(),
          child: pw.Container(
            height: 30,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(border: pw.Border(right: borde)),
            child: pw.Text('CANT.', textAlign: pw.TextAlign.center, style: t(8)),
          ),
        ),
        pw.Expanded(
          flex: (anchos[3] * 100).round(),
          child: pw.Container(
            height: 30,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(border: pw.Border(right: borde)),
            child: pw.Text('PRECIO\nUNITARIO', textAlign: pw.TextAlign.center, style: t(8)),
          ),
        ),
        pw.Expanded(
          flex: ((anchos[4] + anchos[5] + anchos[6]) * 100).round(),
          child: pw.Column(
            children: [
              pw.Container(
                height: 14,
                alignment: pw.Alignment.center,
                decoration: const pw.BoxDecoration(border: pw.Border(bottom: borde)),
                child: pw.Text('VALOR DE VENTAS', style: t(9, spacing: 1.5)),
              ),
              pw.Row(
                children: [
                  for (final (i, txt) in [(4, 'EXENTAS'), (5, '5%'), (6, '10%')])
                    pw.Expanded(
                      flex: (anchos[i] * 100).round(),
                      child: pw.Container(
                        height: 16,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(border: pw.Border(right: i < 6 ? borde : pw.BorderSide.none)),
                        child: pw.Text(txt, style: t(7.5)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // Renglones del talonario: los productos y, debajo, los vacíos hasta [minimo].
  List<pw.Widget> filasDe(int minimo) {
    final filas = <pw.Widget>[];
    for (final l in v.lineas) {
      final valor = miles(l.total);
      filas.add(fila([
        l.unidad == 'unidad' ? l.descripcion : '${l.descripcion} (${l.unidadTexto()})',
        l.nota ?? '',
        cantidad(l.cantidad),
        miles(l.precioNeto),
        l.iva == 0 ? valor : '',
        l.iva == 5 ? valor : '',
        l.iva == 10 ? valor : '',
      ]));
    }
    for (var i = v.lineas.length; i < minimo; i++) {
      filas.add(fila(['', '', '', '', '', '', '']));
    }
    return filas;
  }

  pw.Widget pieFila(pw.Widget izquierda, List<String> montos) => pw.Container(
    decoration: const pw.BoxDecoration(border: pw.Border(top: borde)),
    child: pw.Row(
      children: [
        pw.Expanded(
          flex: ((anchos[0] + anchos[1] + anchos[2] + anchos[3]) * 100).round(),
          child: pw.Container(
            height: 18,
            padding: const pw.EdgeInsets.symmetric(horizontal: 5),
            alignment: pw.Alignment.centerLeft,
            decoration: const pw.BoxDecoration(border: pw.Border(right: borde)),
            child: izquierda,
          ),
        ),
        if (montos.length == 3) ...[
          celda(montos[0], 4, font: r.bold),
          celda(montos[1], 5, font: r.bold),
          celda(montos[2], 6, font: r.bold),
        ] else
          pw.Expanded(
            flex: ((anchos[4] + anchos[5] + anchos[6]) * 100).round(),
            child: pw.Container(
              height: 18,
              padding: const pw.EdgeInsets.symmetric(horizontal: 4),
              alignment: pw.Alignment.centerRight,
              child: pw.Text(montos.single, style: t(10.5, font: r.black)),
            ),
          ),
      ],
    ),
  );
  String m(int x) => x == 0 ? '' : miles(x);

  pw.Widget tabla({required int minimo}) => pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.fromBorderSide(borde), borderRadius: redondo),
    child: pw.Column(
      children: [
        encabezadoTabla,
        ...filasDe(minimo),
        pieFila(pw.Text('SUBTOTALES:', style: t(8.5, font: r.bold)), [m(tot.exentas), m(tot.cinco), m(tot.diez)]),
        pieFila(
          pw.RichText(
            maxLines: 1,
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: 'TOTAL A PAGAR: Guaraníes ',
                  style: t(8.5, font: r.bold),
                ),
                pw.TextSpan(text: _capital(numeroALetras(tot.total)), style: t(8.5)),
              ],
            ),
          ),
          [miles(tot.total)],
        ),
        pw.Container(
          height: 18,
          padding: const pw.EdgeInsets.symmetric(horizontal: 5),
          decoration: const pw.BoxDecoration(border: pw.Border(top: borde)),
          child: pw.Row(
            children: [
              pw.Text('LIQUIDACIÓN DEL IVA:', style: t(8.5, font: r.bold)),
              pw.Spacer(),
              pw.Text('(5%) ', style: t(8.5)),
              pw.Text(m(tot.iva5), style: t(8.5, font: r.bold)),
              pw.Spacer(),
              pw.Text('(10%) ', style: t(8.5)),
              pw.Text(m(tot.iva10), style: t(8.5, font: r.bold)),
              pw.Spacer(),
              pw.Text('TOTAL IVA: ', style: t(8.5)),
              pw.Text(m(tot.ivaTotal), style: t(8.5, font: r.bold)),
            ],
          ),
        ),
        // Pie: imprenta y destino de cada copia (dentro del cuadro, como el talonario).
        pw.Container(
          decoration: const pw.BoxDecoration(border: pw.Border(top: borde)),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Container(
                  height: 26,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  alignment: pw.Alignment.centerLeft,
                  decoration: const pw.BoxDecoration(border: pw.Border(right: borde)),
                  child: pw.Text(nota ? 'Comprobante interno: no válido como factura.' : (f?.pieImprenta ?? ''), style: t(6.5), maxLines: 3),
                ),
              ),
              pw.Container(
                height: 26,
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(nota ? 'Original: Cliente\nCopia: Vendedor' : 'Original: Cliente\nDuplicado: Archivo Tributario', style: t(6.5)),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  pw.Widget cuerpo({int minimo = _filas}) => pw.Column(
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 17, child: negocio),
          pw.SizedBox(width: 12),
          pw.Expanded(flex: 11, child: timbrado),
        ],
      ),
      pw.SizedBox(height: 6),
      datos,
      pw.SizedBox(height: 4),
      tabla(minimo: minimo),
    ],
  );

  const margen = pw.EdgeInsets.fromLTRB(24, 24, 24, 24);
  final tema = pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: margen,
    theme: r.theme,
    buildForeground: v.anulada
        ? (c) => pw.Center(
            child: pw.Transform.rotate(
              angle: 0.5,
              child: pw.Opacity(
                opacity: 0.2,
                child: pw.Text(
                  'ANULADA',
                  style: t(110, font: r.black).copyWith(color: PdfColors.black),
                ),
              ),
            ),
          )
        : null,
  );
  final doc = pw.Document(
    title: nota ? archivoVenta(v, duplicado: duplicado) : archivoFactura(v, duplicado: duplicado),
    author: n.nombre,
    theme: r.theme,
  );
  // Dos copias: la misma factura completa dos veces, una por hoja.
  for (var i = 0; i < (duplicado ? 2 : 1); i++) {
    doc.addPage(pw.Page(pageTheme: tema, build: (c) => cuerpo()));
  }
  return doc.save();
}

/// "4501238-7" -> "4501238 - 7" (como en el talonario).
String _rucConEspacios(String? ruc) => ruc == null ? '' : ruc.replaceAll('-', ' - ');

String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
