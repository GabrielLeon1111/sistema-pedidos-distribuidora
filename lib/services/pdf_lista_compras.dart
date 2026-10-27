import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/negocio.dart';
import '../models/producto.dart';
import '../utils/formato.dart';
import 'pdf_fuentes.dart';

const _negro = PdfColors.black;
const _gris = PdfColor.fromInt(0xFF555555);
const _fondo = PdfColor.fromInt(0xFFEFEFEF);

/// Un producto de la lista de compras y cuánto pedir.
class LineaCompraLista {
  const LineaCompraLista(this.producto, this.cantidad, this.proveedor);
  final Producto producto;
  final double cantidad;

  /// Nombre del proveedor del producto ('' si no tiene).
  final String proveedor;

  int get subtotal => (cantidad * producto.costoReferencia).round();
}

String archivoListaCompras(DateTime fecha) =>
    'Lista_de_compras_${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}.pdf';

/// Lista de lo que hay que comprar, agrupada por proveedor. Con [conPrecios]
/// lleva el último costo y el total estimado (uso interno); sin precios sirve
/// para mandársela al proveedor.
Future<Uint8List> pdfListaCompras(List<LineaCompraLista> lineas, Negocio negocio, {bool conPrecios = true, DateTime? fecha}) async {
  final r = await PdfRecursos.cargar();
  final logo = PdfRecursos.logo(negocio);
  final hoy = fecha ?? DateTime.now();
  pw.TextStyle t(double size, {pw.Font? font, PdfColor color = _negro, double spacing = 0}) =>
      pw.TextStyle(font: font ?? r.regular, fontSize: size, color: color, letterSpacing: spacing);
  const celda = pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5);

  pw.Widget c(String s, {bool derecha = false, bool fuerte = false, PdfColor color = _negro}) => pw.Padding(
        padding: celda,
        child: pw.Text(s, textAlign: derecha ? pw.TextAlign.right : pw.TextAlign.left, style: t(9.5, font: fuerte ? r.bold : r.regular, color: color)),
      );

  final grupos = <String, List<LineaCompraLista>>{};
  for (final l in lineas) {
    (grupos[l.proveedor] ??= []).add(l);
  }
  final total = lineas.fold<int>(0, (s, l) => s + l.subtotal);

  pw.Widget tabla(List<LineaCompraLista> ls) => pw.Table(
        border: pw.TableBorder.all(color: _negro, width: 0.6),
        columnWidths: conPrecios
            ? const {0: pw.FlexColumnWidth(4.2), 1: pw.FlexColumnWidth(1.6), 2: pw.FlexColumnWidth(1.9), 3: pw.FlexColumnWidth(2), 4: pw.FlexColumnWidth(2.2)}
            : const {0: pw.FlexColumnWidth(5), 1: pw.FlexColumnWidth(2.4)},
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _fondo),
            children: [
              c('Producto', fuerte: true),
              // Al proveedor no le sirve nuestro stock: solo va en la lista interna.
              if (conPrecios) c('Stock', fuerte: true, derecha: true),
              c('Pedir', fuerte: true, derecha: true),
              if (conPrecios) ...[c('Últ. costo', fuerte: true, derecha: true), c('Subtotal', fuerte: true, derecha: true)],
            ],
          ),
          for (final l in ls)
            pw.TableRow(children: [
              c('${l.producto.nombre}${l.producto.marca == null ? '' : ' · ${l.producto.marca}'}'),
              if (conPrecios)
                c(l.producto.stock <= 0 ? 'Agotado' : cantidad(l.producto.stock), derecha: true, fuerte: l.producto.stock <= 0),
              c('${cantidad(l.cantidad)} ${unidadPlural(l.producto.unidad, l.cantidad)}', derecha: true, fuerte: true),
              if (conPrecios) ...[
                c(l.producto.costoReferencia > 0 ? miles(l.producto.costoReferencia) : '—', derecha: true),
                c(l.subtotal > 0 ? miles(l.subtotal) : '—', derecha: true),
              ],
            ]),
        ],
      );

  final doc = pw.Document(title: archivoListaCompras(hoy), author: negocio.nombre, theme: r.theme);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}', style: t(8, color: _gris)),
    ),
    build: (ctx) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(negocio.nombre, style: t(19, font: r.serif)),
            if (negocio.ciudad != null || negocio.telefono != null)
              pw.Text([?negocio.ciudad, if (negocio.telefono != null) 'Cel. ${negocio.telefono}'].join(' · '), style: t(9.5, color: _gris)),
            pw.SizedBox(height: 6),
            pw.Text(conPrecios ? 'LISTA DE COMPRAS' : 'PEDIDO DE MERCADERÍA', style: t(16, font: r.black, spacing: 0.4)),
            pw.Text('Fecha: ${fechaCorta.format(hoy)} · ${lineas.length} ${lineas.length == 1 ? 'producto' : 'productos'}', style: t(10, color: _gris)),
          ]),
        ),
        if (logo != null) pw.SizedBox(height: 58, width: 58, child: pw.Image(logo, fit: pw.BoxFit.contain)),
      ]),
      pw.SizedBox(height: 6),
      pw.Container(height: 2, color: _negro),
      for (final g in grupos.entries) ...[
        pw.SizedBox(height: 12),
        pw.Row(children: [
          pw.Expanded(child: pw.Text(g.key.isEmpty ? 'SIN PROVEEDOR CARGADO' : 'PROVEEDOR: ${g.key.toUpperCase()}', style: t(10.5, font: r.black, spacing: 0.6))),
          if (conPrecios) pw.Text('Estimado: ${gs(g.value.fold<int>(0, (s, l) => s + l.subtotal))}', style: t(10, font: r.bold)),
        ]),
        pw.SizedBox(height: 4),
        tabla(g.value),
      ],
      if (conPrecios) ...[
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          color: _fondo,
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text('TOTAL ESTIMADO DE LA COMPRA', style: t(11, font: r.black))),
            pw.Text(gs(total), style: t(13, font: r.black)),
          ]),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Estimado con el costo de la última compra de cada producto (o el costo promedio del stock).', style: t(8.5, color: _gris)),
      ],
      pw.SizedBox(height: 26),
      pw.Row(children: [
        pw.Expanded(child: pw.Column(children: [pw.Container(height: 0.7, color: _negro), pw.SizedBox(height: 3), pw.Text('Pedido por', style: t(9, color: _gris))])),
        pw.SizedBox(width: 40),
        pw.Expanded(child: pw.Column(children: [pw.Container(height: 0.7, color: _negro), pw.SizedBox(height: 3), pw.Text('Recibido / confirmado', style: t(9, color: _gris))])),
      ]),
    ],
  ));
  return doc.save();
}
