import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre el menú de compartir del sistema (WhatsApp, correo, etc.) con el archivo.
Future<void> compartirArchivo(Uint8List bytes, String nombre, {String? texto, String mime = 'application/pdf'}) async {
  if (kIsWeb) return _compartirWeb([(bytes, nombre)], texto: texto, mime: mime);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$nombre');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], text: texto, subject: nombre));
}

/// Comparte varios archivos juntos (las hojas de una nota larga en imágenes).
Future<void> compartirArchivos(List<(Uint8List, String)> archivos, {String? texto, String mime = 'image/png'}) async {
  if (archivos.length == 1) return compartirArchivo(archivos.first.$1, archivos.first.$2, texto: texto, mime: mime);
  if (kIsWeb) return _compartirWeb(archivos, texto: texto, mime: mime);
  final dir = await getTemporaryDirectory();
  final files = <XFile>[];
  for (final (bytes, nombre) in archivos) {
    final file = File('${dir.path}${Platform.pathSeparator}$nombre');
    await file.writeAsBytes(bytes, flush: true);
    files.add(XFile(file.path, mimeType: mime));
  }
  await SharePlus.instance.share(ShareParams(files: files, text: texto));
}

/// En el navegador: el menú de compartir si el navegador lo tiene (celular);
/// si no (la mayoría de las computadoras), se descargan los archivos.
Future<void> _compartirWeb(List<(Uint8List, String)> archivos, {String? texto, required String mime}) async {
  try {
    final r = await SharePlus.instance.share(
      ShareParams(files: [for (final (b, n) in archivos) XFile.fromData(b, name: n, mimeType: mime)], text: texto),
    );
    if (r.status != ShareResultStatus.unavailable) return;
  } catch (_) {
    // El navegador no deja compartir archivos: se descargan.
  }
  for (final (b, n) in archivos) {
    await _descargarWeb(b, n, mime);
  }
}

/// Descarga el archivo desde el navegador (va a la carpeta Descargas).
Future<void> _descargarWeb(Uint8List bytes, String nombre, String mime) =>
    XFile.fromData(bytes, name: nombre, mimeType: mime).saveTo(nombre);

/// La app corre en una computadora (Windows, Linux o Mac).
bool get esComputadora => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

const _archivos = MethodChannel('sistema_pedidos/archivos');

/// Guarda el archivo en el equipo.
/// - Navegador: se descarga (carpeta Descargas).
/// - Computadora: en la carpeta Descargas, y la abre.
/// - Celular Android: el PDF (o Excel) en Descargas y la imagen en la galería,
///   sin preguntar nada. Si el teléfono no deja (Android muy viejo), se comparte.
/// Devuelve dónde quedó, para avisar al usuario (null si se compartió).
Future<String?> guardarArchivo(Uint8List bytes, String nombre, {bool esPdf = true, String? mime}) async {
  if (kIsWeb) {
    await _descargarWeb(bytes, nombre, mime ?? (esPdf ? 'application/pdf' : 'application/octet-stream'));
    return 'Descargas';
  }
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    var file = File('${dir.path}${Platform.pathSeparator}$nombre');
    var n = 1;
    while (await file.exists()) {
      final punto = nombre.lastIndexOf('.');
      file = File('${dir.path}${Platform.pathSeparator}${nombre.substring(0, punto)} ($n)${nombre.substring(punto)}');
      n++;
    }
    await file.writeAsBytes(bytes, flush: true);
    await launchUrl(Uri.file(file.path));
    return file.path;
  }
  final tipo = mime ?? (esPdf ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  if (Platform.isAndroid) {
    try {
      return await _archivos.invokeMethod<String>('guardar', {'bytes': bytes, 'nombre': nombre, 'mime': tipo});
    } catch (_) {
      // Sin permiso para guardar: se comparte (de ahí se guarda en Archivos).
      await compartirArchivo(bytes, nombre, mime: tipo);
      return null;
    }
  }
  if (esPdf) {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: nombre);
  } else {
    // En el celular: Excel o imagen se comparten (desde ahí se guardan en Archivos o en la galería).
    await compartirArchivo(bytes, nombre, mime: mime ?? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }
  return null;
}

Future<void> imprimirPdf(Uint8List bytes, String nombre) => Printing.layoutPdf(onLayout: (_) async => bytes, name: nombre);

/// Abre un chat de WhatsApp con ese número (formato 595...).
Future<bool> abrirWhatsapp(String numero, {String texto = ''}) =>
    launchUrl(Uri.parse('https://wa.me/$numero?text=${Uri.encodeComponent(texto)}'), mode: LaunchMode.externalApplication);
