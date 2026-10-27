import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../security/registro_seguro.dart';
import '../services/compartir.dart';
import '../services/imagen_pdf.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import 'common.dart';

enum FormatoDoc { pdf, imagen }

/// Botones para un documento: elegir PDF o imagen y mandarlo por WhatsApp con
/// un mensaje automático o descargarlo; el PDF además se imprime. El documento
/// queda guardado en la app aunque no se envíe.
class DocActions extends StatefulWidget {
  const DocActions({
    super.key,
    required this.build,
    required this.fileName,
    this.shareText,
    this.telefono,
    this.destinatario,
  });

  /// Genera el PDF (las imágenes se sacan del PDF, una por hoja).
  final Future<Uint8List> Function() build;
  final String fileName;

  /// Mensaje automático que acompaña al archivo.
  final String? shareText;

  /// Celular del destinatario: si está, aparece el botón para abrir su chat con el mensaje escrito.
  final String? telefono;
  final String? destinatario;

  @override
  State<DocActions> createState() => _DocActionsState();
}

class _DocActionsState extends State<DocActions> {
  String? _busy;
  Uint8List? _pdf;
  List<Uint8List>? _pngs;
  FormatoDoc _formato = FormatoDoc.pdf;

  bool get _esImagen => _formato == FormatoDoc.imagen;

  @override
  void didUpdateWidget(covariant DocActions old) {
    super.didUpdateWidget(old);
    // Si cambió el documento (ej: se ajustó la nota), se vuelve a generar.
    if (old.fileName != widget.fileName || old.build != widget.build) {
      _pdf = null;
      _pngs = null;
    }
  }

  Future<List<(Uint8List, String)>> _archivos() async {
    final pdf = _pdf ??= await widget.build();
    if (!_esImagen) return [(pdf, widget.fileName)];
    final pngs = _pngs ??= await pdfAImagenes(pdf);
    return [
      for (var i = 0; i < pngs.length; i++) (pngs[i], nombreImagen(widget.fileName, hoja: i + 1, hojas: pngs.length)),
    ];
  }

  Future<void> _run(String key, Future<void> Function(List<(Uint8List, String)> archivos) action) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      await action(await _archivos());
    } catch (e) {
      registrarError('doc_$key', e);
      if (mounted) {
        showSnack(context, mensajeErrorSeguro(e, _esImagen ? 'No se pudo generar la imagen. Intentá de nuevo.' : 'No se pudo generar el PDF. Intentá de nuevo.'),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _abrirChat(String numero) async {
    final ok = await abrirWhatsapp(numero, texto: widget.shareText ?? '');
    if (!ok && mounted) showSnack(context, 'No se pudo abrir WhatsApp.', error: true);
  }

  Widget _spinner([Color? color]) => SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: color));

  @override
  Widget build(BuildContext context) {
    final numero = telefonoWhatsapp(widget.telefono);
    final quien = widget.destinatario?.trim().split(RegExp(r'\s+')).first;
    final mime = _esImagen ? 'image/png' : 'application/pdf';

    final formato = SegmentedButton<FormatoDoc>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: FormatoDoc.pdf, label: Text('PDF'), icon: Icon(Icons.picture_as_pdf_outlined)),
        ButtonSegment(value: FormatoDoc.imagen, label: Text('Imagen'), icon: Icon(Icons.image_outlined)),
      ],
      selected: {_formato},
      onSelectionChanged: _busy != null ? null : (v) => setState(() => _formato = v.first),
    );

    final whatsapp = FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: AppColors.whatsapp, foregroundColor: Colors.white, minimumSize: const Size(0, 52)),
      onPressed: () => _run('share', (a) => compartirArchivos(a, texto: widget.shareText, mime: mime)),
      icon: _busy == 'share' ? _spinner(Colors.white) : const Icon(Icons.send_rounded),
      label: Text(_esImagen ? 'Enviar imagen por WhatsApp' : 'Enviar PDF por WhatsApp'),
    );

    final save = OutlinedButton.icon(
      onPressed: () {
        final messenger = ScaffoldMessenger.of(context);
        _run('save', (a) async {
          String? donde;
          for (final (b, n) in a) {
            donde = await guardarArchivo(b, n, esPdf: !_esImagen, mime: mime);
          }
          if (donde == null) return;
          final que = _esImagen ? (a.length > 1 ? '${a.length} imágenes guardadas' : 'Imagen guardada') : 'PDF guardado';
          final lugar = switch (donde) {
            'Galería' => 'en la galería (Distribuidora AM)',
            'Descargas' => 'en Descargas',
            _ => 'en $donde',
          };
          messenger.showSnackBar(SnackBar(content: Text('$que $lugar')));
        });
      },
      icon: _busy == 'save' ? _spinner() : const Icon(Icons.download_rounded),
      label: const Text('Descargar'),
    );

    // Imprimir solo aparece con PDF (sale mejor que la imagen).
    final print = OutlinedButton.icon(
      onPressed: () => _run('print', (_) async => imprimirPdf(_pdf ??= await widget.build(), widget.fileName)),
      icon: _busy == 'print' ? _spinner() : const Icon(Icons.print_outlined),
      label: const Text('Imprimir'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        formato,
        const SizedBox(height: 10),
        whatsapp,
        if (widget.shareText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              'Va con el mensaje: "${widget.shareText}"',
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (numero != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.whatsapp, side: const BorderSide(color: AppColors.whatsapp)),
            onPressed: () => _abrirChat(numero),
            icon: const Icon(Icons.chat_outlined),
            label: Text('Abrir el chat de ${quien == null || quien.isEmpty ? 'cliente' : quien} con el mensaje', overflow: TextOverflow.ellipsis),
          ),
        ],
        const SizedBox(height: 10),
        // PDF: enviar, descargar e imprimir. Imagen: enviar y descargar (se imprime el PDF).
        if (_esImagen) save else Row(children: [Expanded(child: save), const SizedBox(width: 10), Expanded(child: print)]),
      ],
    );
  }
}
