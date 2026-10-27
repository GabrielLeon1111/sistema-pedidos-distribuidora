import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/cliente.dart';
import '../models/negocio.dart';
import '../utils/formato.dart';
import 'pdf_fuentes.dart';

/// Piezas comunes de todos los documentos: encabezado con logo y datos del
/// negocio, caja del cliente, tablas, pie y sello de ANULADO.
class PdfBase {
  PdfBase(this.r, this.negocio) : logo = PdfRecursos.logo(negocio);

  final PdfRecursos r;
  final Negocio negocio;
  final pw.ImageProvider? logo;

  static Future<PdfBase> crear(Negocio n) async => PdfBase(await PdfRecursos.cargar(), n);

  pw.TextStyle t(double size, {pw.Font? font, PdfColor color = ColoresPdf.tinta, double spacing = 0}) =>
      pw.TextStyle(font: font ?? r.regular, fontSize: size, color: color, letterSpacing: spacing);

  /// Encabezado: logo + negocio a la izquierda, tipo de documento y número a la derecha.
  pw.Widget encabezado({required String titulo, required String numero, required DateTime fecha, List<String> extra = const []}) {
    final datos = [
      if (negocio.ruc != null) 'RUC ${negocio.ruc}',
      if (negocio.telefono != null) 'Tel. ${negocio.telefono}',
      ?negocio.direccion,
      ?negocio.ciudad,
    ];
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: ColoresPdf.acento, width: 2))),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) ...[
            pw.SizedBox(width: 62, height: 62, child: pw.Image(logo!, fit: pw.BoxFit.contain)),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(negocio.nombre, style: t(20, font: r.serif)),
                pw.Text(negocio.rubro.toUpperCase(), style: t(8.5, font: r.bold, color: ColoresPdf.acento, spacing: 1)),
                if (datos.isNotEmpty) ...[pw.SizedBox(height: 3), pw.Text(datos.join(' · '), style: t(8.5, color: ColoresPdf.gris))],
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: pw.BoxDecoration(color: ColoresPdf.acentoSuave, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(titulo.toUpperCase(), style: t(11, font: r.black, color: ColoresPdf.acento, spacing: 0.6)),
                pw.Text('N° $numero', style: t(14, font: r.black)),
                pw.Text(fechaHora.format(fecha), style: t(9, color: ColoresPdf.gris)),
                for (final e in extra) pw.Text(e, style: t(9, color: ColoresPdf.gris)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _dato(String etiqueta, String? valor) => pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(text: '$etiqueta: ', style: t(9.5, font: r.bold)),
          pw.TextSpan(text: (valor == null || valor.isEmpty) ? '—' : valor, style: t(9.5)),
        ]),
      );

  /// Datos del local para facturar.
  pw.Widget cajaCliente(DatosCliente c, {String titulo = 'Cliente'}) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10, bottom: 10),
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: ColoresPdf.linea), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(titulo.toUpperCase(), style: t(8, font: r.bold, color: ColoresPdf.gris, spacing: 0.8)),
            pw.SizedBox(height: 3),
            pw.Text(c.nombre, style: t(13, font: r.black)),
            pw.SizedBox(height: 4),
            pw.Wrap(spacing: 16, runSpacing: 3, children: [
              if (c.razonSocial != null) _dato('Razón social', c.razonSocial),
              if (c.ruc != null) _dato('RUC', c.ruc),
              if (c.telefono != null) _dato('Tel.', c.telefono),
              if (c.contacto != null) _dato('Contacto', c.contacto),
              if (c.direccion != null) _dato('Dirección', c.direccion),
            ]),
          ],
        ),
      );

  pw.Widget celda(String texto, {bool derecha = false, pw.Font? font, double size = 9.5, PdfColor? color, bool tachado = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(
          texto,
          textAlign: derecha ? pw.TextAlign.right : pw.TextAlign.left,
          style: t(size, font: font, color: color ?? ColoresPdf.tinta).copyWith(decoration: tachado ? pw.TextDecoration.lineThrough : null),
        ),
      );

  pw.TableRow filaTitulos(List<String> titulos, {Set<int> derecha = const {}}) => pw.TableRow(
        decoration: const pw.BoxDecoration(color: ColoresPdf.acentoSuave),
        children: [
          for (var i = 0; i < titulos.length; i++) celda(titulos[i], derecha: derecha.contains(i), font: r.bold, color: ColoresPdf.tinta, size: 9),
        ],
      );

  /// Fila de totales (etiqueta a la izquierda, monto a la derecha).
  pw.Widget filaTotal(String etiqueta, String valor, {bool fuerte = false, PdfColor? color}) => pw.Container(
        padding: pw.EdgeInsets.symmetric(horizontal: 8, vertical: fuerte ? 6 : 3),
        color: fuerte ? ColoresPdf.acentoSuave : null,
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(etiqueta, style: t(fuerte ? 12 : 10, font: fuerte ? r.black : r.medium, color: color ?? ColoresPdf.tinta))),
          pw.Text(valor, style: t(fuerte ? 14 : 10, font: fuerte ? r.black : r.bold, color: color ?? ColoresPdf.tinta)),
        ]),
      );

  pw.Widget pie({String? observaciones, String aviso = 'Documento de control. No válido como factura.'}) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (observaciones != null) ...[pw.SizedBox(height: 10), pw.Text('Observaciones: $observaciones', style: t(9.5))],
          if (negocio.notaPie != null) ...[pw.SizedBox(height: 8), pw.Text(negocio.notaPie!, style: t(9, color: ColoresPdf.gris))],
          pw.SizedBox(height: 10),
          pw.Text(aviso, style: t(8, color: ColoresPdf.gris)),
        ],
      );

  /// Documento de varias hojas con número de página y sello de ANULADO si corresponde.
  pw.Document documento({required String titulo, required List<pw.Widget> Function(pw.Context) contenido, bool anulado = false}) {
    final doc = pw.Document(title: titulo, author: negocio.nombre, theme: r.theme);
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
          theme: r.theme,
          buildForeground: anulado
              ? (c) => pw.Center(
                    child: pw.Transform.rotate(
                      angle: 0.5,
                      child: pw.Opacity(opacity: 0.2, child: pw.Text('ANULADO', style: t(110, font: r.black, color: ColoresPdf.alerta))),
                    ),
                  )
              : null,
        ),
        footer: (c) => c.pagesCount > 1
            ? pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Hoja ${c.pageNumber} de ${c.pagesCount}', style: t(8, color: ColoresPdf.gris)))
            : pw.SizedBox(),
        build: contenido,
      ),
    );
    return doc;
  }
}
