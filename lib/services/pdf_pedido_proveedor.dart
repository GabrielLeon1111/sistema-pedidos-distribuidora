import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/consolidado.dart';
import '../models/negocio.dart';
import '../utils/formato.dart';
import 'pdf_factura.dart';
import 'pdf_fuentes.dart';

const _negro = PdfColors.black;
const _borde = pw.BorderSide(color: _negro, width: 0.9);
const _bordeFino = pw.BorderSide(color: _negro, width: 0.4);

/// Renglones mínimos de la tabla (como el talonario).
const _filas = 12;

/// Nota de pedido al proveedor: el total de lo que se levantó en todos los
/// locales, sumado por producto, con el mismo diseño de la factura.
/// [conPrecios]: agrega el último precio de compra y el total estimado.
/// [categorias]: la categoría de cada producto (por id); los productos salen
/// separados por categoría, con su título.
Future<Uint8List> pdfPedidoProveedor(Consolidado c, Negocio n, {bool conPrecios = false, Map<String, String?> categorias = const {}}) async {
  final r = await PdfRecursos.cargar();
  pw.TextStyle t(double size, {pw.Font? font, double spacing = 0}) =>
      pw.TextStyle(font: font ?? r.regular, fontSize: size, color: _negro, letterSpacing: spacing);
  final redondo = pw.BorderRadius.circular(8);

  final numero = pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(border: pw.Border.fromBorderSide(_borde), borderRadius: redondo),
    child: pw.Column(
      children: [
        pw.SizedBox(height: 10),
        pw.Text('RUC: ${(n.ruc ?? '').replaceAll('-', ' - ')}', style: t(11, font: r.medium)),
        pw.SizedBox(height: 6),
        pw.Text('NOTA DE PEDIDO', style: t(15, font: r.serif, spacing: 3)),
        pw.SizedBox(height: 4),
        pw.Text('N° ${nroDoc(c.numero)}', style: t(17, font: r.medium, spacing: 0.5)),
        pw.SizedBox(height: 10),
      ],
    ),
  );

  pw.Widget campo(String etiqueta, String? valor) => pw.Row(
    children: [
      pw.Text('$etiqueta ', style: t(8.5)),
      pw.Expanded(
        child: pw.Text(valor ?? '', style: t(9.5, font: r.medium), maxLines: 1),
      ),
    ],
  );
  pw.Widget renglon(List<pw.Widget> hijos, {bool ultimo = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
    decoration: ultimo ? null : const pw.BoxDecoration(border: pw.Border(bottom: _borde)),
    child: pw.Row(children: hijos),
  );
  final datos = pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.fromBorderSide(_borde), borderRadius: redondo),
    child: pw.Column(
      children: [
        renglon([
          pw.Expanded(flex: 5, child: campo('Fecha:', fechaHora.format(c.fecha))),
          pw.Expanded(flex: 6, child: campo('Pedidos de locales:', '${c.pedidoIds.length}')),
        ]),
        renglon([
          pw.Expanded(flex: 7, child: campo('Proveedor:', c.proveedorNombre)),
          pw.Expanded(flex: 4, child: campo('Tel.:', c.proveedorTelefono)),
        ]),
        renglon([pw.Expanded(child: campo('Pedido por:', c.creadoPor))], ultimo: true),
      ],
    ),
  );

  // ---------- Tabla: el total de cada producto ----------
  // Producto | Descripción (el detalle: colores, talles...) | Cantidad [| Precio | Total]
  final anchos = conPrecios
      ? const {
          0: pw.FlexColumnWidth(3.6),
          1: pw.FlexColumnWidth(2.6),
          2: pw.FlexColumnWidth(1.4),
          3: pw.FlexColumnWidth(1.3),
          4: pw.FlexColumnWidth(1.4),
        }
      : const {0: pw.FlexColumnWidth(4.0), 1: pw.FlexColumnWidth(3.2), 2: pw.FlexColumnWidth(1.6)};
  pw.Widget celda(String s, {bool derecha = false, bool centro = false, pw.Font? font, double size = 9}) => pw.Container(
    height: 17,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4),
    alignment: centro ? pw.Alignment.center : (derecha ? pw.Alignment.centerRight : pw.Alignment.centerLeft),
    child: pw.Text(s, style: t(size, font: font), maxLines: 1),
  );
  pw.Widget titulo(String s, {double spacing = 0}) => pw.Container(
    height: 22,
    alignment: pw.Alignment.center,
    child: pw.Text(s, style: t(8.5, spacing: spacing)),
  );
  final totalUnidades = c.lineas.fold<double>(0, (s, l) => s + l.cantidad);
  final totalEstimado = c.lineas.fold<int>(0, (s, l) => s + (l.cantidad * l.precioCompra).round());
  // Separados por categoría: el título de cada una y debajo sus productos.
  String cat(LineaConsolidado l) => (l.productoId == null ? null : categorias[l.productoId]) ?? 'Sin categoría';
  final grupos = ({for (final l in c.lineas) cat(l)}.toList()..sort());
  final filas = <Object>[
    for (final g in grupos) ...[
      if (grupos.length > 1) g,
      for (final l in c.lineas)
        if (cat(l) == g) l,
    ],
  ];
  final tabla = pw.Table(
    border: const pw.TableBorder(left: _borde, right: _borde, top: _borde, bottom: _borde, verticalInside: _borde, horizontalInside: _bordeFino),
    columnWidths: anchos,
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: _borde)),
        children: [
          titulo('PRODUCTO', spacing: 2),
          titulo('DESCRIPCIÓN', spacing: 2),
          titulo('CANTIDAD'),
          if (conPrecios) ...[titulo('PRECIO UNIT.'), titulo('TOTAL')],
        ],
      ),
      for (final fila in filas)
        if (fila is String)
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              celda(fila.toUpperCase(), font: r.bold, size: 8.5),
              for (var k = 1; k < anchos.length; k++) celda(''),
            ],
          )
        else if (fila is LineaConsolidado)
          pw.TableRow(
            children: [
              for (final l in [fila]) ...[
                celda(l.codigo == null ? l.descripcion : '${l.descripcion}  (Cód. ${l.codigo})'),
                pw.Container(
                  constraints: const pw.BoxConstraints(minHeight: 17),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(l.nota ?? '', style: t(8.5), maxLines: 3),
                ),
                celda('${cantidad(l.cantidad)} ${textoForma(l.unidad, l.factor, l.cantidad)}', centro: true, font: r.bold),
                if (conPrecios) ...[
                  celda(l.precioCompra > 0 ? miles(l.precioCompra) : '', derecha: true),
                  celda(l.precioCompra > 0 ? miles((l.cantidad * l.precioCompra).round()) : '', derecha: true),
                ],
              ],
            ],
          ),
      for (var i = filas.length; i < _filas; i++) pw.TableRow(children: [for (var k = 0; k < anchos.length; k++) celda('')]),
    ],
  );

  pw.Widget pieFila(pw.Widget izquierda, String derecha) => pw.Container(
    height: 20,
    padding: const pw.EdgeInsets.symmetric(horizontal: 5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(left: _borde, right: _borde, bottom: _borde),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(child: izquierda),
        pw.Text(derecha, style: t(10.5, font: r.black)),
      ],
    ),
  );

  final doc = pw.Document(title: archivoPedidoProveedor(c), author: n.nombre, theme: r.theme);
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(24), theme: r.theme),
      footer: (ctx) => ctx.pagesCount > 1
          ? pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Hoja ${ctx.pageNumber} de ${ctx.pagesCount}', style: t(8)),
            )
          : pw.SizedBox(),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(flex: 17, child: encabezadoTalonario(n, r)),
            pw.SizedBox(width: 12),
            pw.Expanded(flex: 11, child: numero),
          ],
        ),
        pw.SizedBox(height: 6),
        datos,
        pw.SizedBox(height: 4),
        tabla,
        pieFila(
          pw.Text('TOTAL: ${c.lineas.length} productos · ${cantidad(totalUnidades)} unidades', style: t(8.5, font: r.bold)),
          conPrecios && totalEstimado > 0 ? gs(totalEstimado) : '',
        ),
        pieFila(pw.Text('Por favor confirmar precios y disponibilidad. ¡Gracias!', style: t(8)), ''),
        if (conPrecios) ...[pw.SizedBox(height: 3), pw.Text('Precios: el último precio de compra de cada producto. Total estimado.', style: t(7.5))],
      ],
    ),
  );
  return doc.save();
}

String archivoPedidoProveedor(Consolidado c) => 'Nota_de_pedido_proveedor_${nroDoc(c.numero)}.pdf';
