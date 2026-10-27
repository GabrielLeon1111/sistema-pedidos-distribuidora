import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/negocio.dart';

/// Tipografías para los PDF (se cargan una sola vez).
class PdfRecursos {
  PdfRecursos._(this.regular, this.medium, this.bold, this.black, this.serif);

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font bold;
  final pw.Font black;
  final pw.Font serif;

  static PdfRecursos? _cache;

  static Future<PdfRecursos> cargar() async {
    if (_cache != null) return _cache!;
    Future<pw.Font> f(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name'));
    _cache = PdfRecursos._(
      await f('Barlow-Regular.ttf'),
      await f('Barlow-Medium.ttf'),
      await f('Barlow-SemiBold.ttf'),
      await f('Barlow-Bold.ttf'),
      await f('DMSerifDisplay-Regular.ttf'),
    );
    return _cache!;
  }

  pw.ThemeData get theme => pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold);

  /// Logo cargado en "Datos del negocio" (null si no hay).
  static pw.ImageProvider? logo(Negocio n) {
    final bytes = n.logo;
    if (bytes == null) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }
}

/// Colores de los documentos: todo en blanco y negro (negro y grises), para
/// imprimir en cualquier impresora y que se lea igual en fotocopia.
abstract final class ColoresPdf {
  /// Títulos, líneas fuertes y totales.
  static const acento = PdfColor.fromInt(0xFF000000);

  /// Fondo de los títulos de tabla y del recuadro del número.
  static const acentoSuave = PdfColor.fromInt(0xFFE6E6E6);
  static const tinta = PdfColor.fromInt(0xFF000000);
  static const gris = PdfColor.fromInt(0xFF555555);
  static const linea = PdfColor.fromInt(0xFFBDBDBD);
  static const fondo = PdfColor.fromInt(0xFFF3F3F3);

  /// Lo que hay que mirar (saldo, anulado): negro, se destaca con negrita.
  static const alerta = PdfColor.fromInt(0xFF000000);

  /// Avisos secundarios (parcial, del stock).
  static const aviso = PdfColor.fromInt(0xFF444444);
}
