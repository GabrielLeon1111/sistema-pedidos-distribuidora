import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:printing/printing.dart';

/// Convierte un PDF en imágenes PNG (para mandar por WhatsApp como foto, que se
/// ve directo en el chat). Las notas largas salen en varias imágenes: una por hoja.
Future<List<Uint8List>> pdfAImagenes(Uint8List pdf, {double dpi = 160}) async {
  final r = <Uint8List>[];
  await for (final p in Printing.raster(pdf, dpi: dpi)) {
    r.add(await _png(await _conFondoBlanco(await p.toImage())));
  }
  if (r.isEmpty) throw StateError('El PDF no tiene páginas');
  return r;
}

/// Las páginas del PDF salen con fondo transparente: WhatsApp y la galería lo
/// muestran en negro. Siempre se pinta un fondo blanco debajo.
Future<ui.Image> _conFondoBlanco(ui.Image pagina) async {
  final grabador = ui.PictureRecorder();
  final lienzo = ui.Canvas(grabador);
  lienzo.drawRect(ui.Rect.fromLTWH(0, 0, pagina.width.toDouble(), pagina.height.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  lienzo.drawImage(pagina, ui.Offset.zero, ui.Paint());
  return grabador.endRecording().toImage(pagina.width, pagina.height);
}

Future<Uint8List> _png(ui.Image imagen) async {
  final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
  return datos!.buffer.asUint8List();
}

/// "Pedido_000128.pdf" -> "Pedido_000128.png" (o "Pedido_000128_hoja2.png").
String nombreImagen(String nombrePdf, {int hoja = 1, int hojas = 1}) {
  final base = nombrePdf.toLowerCase().endsWith('.pdf') ? nombrePdf.substring(0, nombrePdf.length - 4) : nombrePdf;
  return hojas > 1 ? '${base}_hoja$hoja.png' : '$base.png';
}
