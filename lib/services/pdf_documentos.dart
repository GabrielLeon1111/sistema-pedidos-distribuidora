import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import '../models/consolidado.dart';
import '../models/linea.dart';
import '../models/negocio.dart';
import '../models/pago.dart';
import '../models/pedido.dart';
import '../models/venta.dart';
import '../utils/formato.dart';
import 'pdf_base.dart';
import 'pdf_factura.dart';
import 'pdf_pedido_proveedor.dart';
import 'pdf_fuentes.dart';

String _primerNombre(String n) => n.trim().split(RegExp(r'\s+')).first;

String archivoPedido(Pedido p) => 'Pedido_${nroDoc(p.numero)}_${_primerNombre(p.cliente.nombre)}.pdf';
String archivoVenta(Venta v, {bool duplicado = false}) =>
    'Nota_de_venta_${nroDoc(v.numero)}_${_primerNombre(v.cliente.nombre)}${duplicado ? '_2_copias' : ''}.pdf';
String archivoRecibo(Pago p) => 'Recibo_${nroDoc(p.numero)}_${_primerNombre(p.clienteNombre)}.pdf';
String archivoConsolidado(Consolidado c) => archivoPedidoProveedor(c);
String archivoRecepcion(Consolidado c) => 'Recepcion_${nroDoc(c.numero)}.pdf';

/// Tabla de productos (nota de pedido o de venta):
/// Producto | Descripción (el detalle: colores, talles...) | Cant. | Precio | Desc. | Total.
pw.Widget _tablaLineas(PdfBase b, List<Linea> lineas, {required bool esPedido}) {
  final filas = <pw.TableRow>[
    b.filaTitulos(['Producto', 'Descripción', 'Cant.', 'Precio', 'Desc.', 'Total'], derecha: {2, 3, 4, 5}),
  ];
  for (var i = 0; i < lineas.length; i++) {
    final l = lineas[i];
    // Avisos de la línea (van chiquitos debajo del producto).
    final avisos = <String>[
      if (l.codigo != null) 'Cód. ${l.codigo}',
      if (esPedido && l.estado == EstadoLinea.parcial) 'Pidió ${cantidad(l.cantidad)}, llegó ${cantidad(l.cantidadEfectiva)}',
      if (esPedido && l.anulada) l.estado.texto,
      if (esPedido && l.deStock) 'Del stock',
    ];
    final desc = l.descuento > 0 ? (l.descPct != null ? '${cantidad(l.descPct!)}%' : miles(l.descuento)) : '';
    final tachado = l.anulada ? pw.TextDecoration.lineThrough : null;
    filas.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: i.isOdd ? ColoresPdf.fondo : null),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(l.unidad == 'unidad' ? l.descripcion : '${l.descripcion} (${l.unidadTexto(l.cantidadEfectiva)})',
                style: b.t(9.5).copyWith(decoration: tachado)),
            if (avisos.isNotEmpty) pw.Text(avisos.join(' · '), style: b.t(7.5, color: l.anulada ? ColoresPdf.alerta : ColoresPdf.aviso)),
          ]),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: pw.Text(l.nota ?? '', style: b.t(8.5).copyWith(decoration: tachado)),
        ),
        b.celda(cantidad(l.cantidadEfectiva), derecha: true, tachado: l.anulada),
        b.celda(miles(l.precio), derecha: true),
        b.celda(desc, derecha: true),
        b.celda(miles(l.total), derecha: true, font: b.r.bold),
      ],
    ));
  }
  return pw.Table(
    border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: ColoresPdf.linea, width: 0.5), bottom: pw.BorderSide(color: ColoresPdf.linea)),
    columnWidths: const {
      0: pw.FlexColumnWidth(3.4),
      1: pw.FlexColumnWidth(2.4),
      2: pw.FlexColumnWidth(0.8),
      3: pw.FlexColumnWidth(1.3),
      4: pw.FlexColumnWidth(0.9),
      5: pw.FlexColumnWidth(1.4),
    },
    children: filas,
  );
}

pw.Widget _totales(PdfBase b, List<Linea> lineas, {int? pagado, int? saldo, int? sena}) {
  final bruto = lineas.fold<int>(0, (s, l) => s + l.bruto);
  final desc = lineas.fold<int>(0, (s, l) => s + l.descuento);
  final total = bruto - desc;
  return pw.Row(children: [
    pw.Spacer(flex: 5),
    pw.Expanded(
      flex: 4,
      child: pw.Column(children: [
        pw.SizedBox(height: 6),
        if (desc > 0) ...[b.filaTotal('Subtotal', gs(bruto)), b.filaTotal('Descuentos', '− ${gs(desc)}')],
        b.filaTotal('TOTAL', gs(total), fuerte: true),
        if (sena != null && sena > 0) b.filaTotal('Seña / adelanto', gs(sena)),
        if (pagado != null) b.filaTotal('Pagado', gs(pagado)),
        if (saldo != null) b.filaTotal('Saldo pendiente', gs(saldo), color: saldo > 0 ? ColoresPdf.alerta : ColoresPdf.acento),
      ]),
    ),
  ]);
}

/// Nota de pedido (con lo que realmente se entrega si ya llegó la mercadería).
Future<Uint8List> pdfNotaPedido(Pedido p, Negocio n, {int sena = 0}) async {
  final b = await PdfBase.crear(n);
  final extra = [
    if (p.vendedorNombre != null) 'Atendió: ${p.vendedorNombre}',
    if (p.fechaEntrega != null) 'Entrega: ${fechaCorta.format(p.fechaEntrega!)}',
  ];
  final doc = b.documento(
    titulo: archivoPedido(p),
    anulado: p.estado == EstadoPedido.anulado,
    contenido: (c) => [
      b.encabezado(titulo: 'Nota de pedido', numero: nroDoc(p.numero), fecha: p.fecha, extra: extra),
      b.cajaCliente(p.cliente),
      _tablaLineas(b, p.lineas, esPedido: true),
      _totales(b, p.lineas, sena: sena),
      b.pie(observaciones: p.observaciones),
    ],
  );
  return doc.save();
}

/// Nota de venta: el mismo diseño que la factura, sin timbrado ni vigencias.
/// Con [duplicado] sale dos veces, una en cada hoja (cliente y vendedor).
Future<Uint8List> pdfNotaVenta(Venta v, Negocio n, {bool duplicado = false}) => pdfFactura(v, n, duplicado: duplicado, nota: true);

/// Recibo de pago.
Future<Uint8List> pdfRecibo(Pago p, Negocio n, {int? saldoRestante}) async {
  final b = await PdfBase.crear(n);
  final concepto = [
    if (p.esSena) 'Seña / adelanto del pedido N° ${nroDoc(p.pedidoNumero ?? 0)}',
    for (final a in p.aplicaciones) 'Nota de venta N° ${nroDoc(a.ventaNumero)}: ${gs(a.monto)}',
    if (p.aFavor > 0 && !p.esSena) 'A favor del local: ${gs(p.aFavor)}',
  ];
  final doc = b.documento(
    titulo: archivoRecibo(p),
    anulado: p.anulado,
    contenido: (c) => [
      b.encabezado(titulo: 'Recibo de pago', numero: nroDoc(p.numero), fecha: p.fecha),
      pw.SizedBox(height: 14),
      pw.Text('Recibimos de', style: b.t(10, color: ColoresPdf.gris)),
      pw.Text(p.clienteNombre, style: b.t(18, font: b.r.black)),
      pw.SizedBox(height: 12),
      pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(color: ColoresPdf.acentoSuave, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text('LA SUMA DE', style: b.t(11, font: b.r.bold, color: ColoresPdf.acento, spacing: 1))),
          pw.Text(gs(p.monto), style: b.t(26, font: b.r.black)),
        ]),
      ),
      pw.SizedBox(height: 12),
      b.filaTotal('Forma de pago', metodoPagoTexto(p.metodo)),
      if (p.registradoPor != null) b.filaTotal('Recibió', p.registradoPor!),
      if (saldoRestante != null && !p.anulado)
        b.filaTotal('Saldo pendiente del local', gs(saldoRestante), color: saldoRestante > 0 ? ColoresPdf.alerta : ColoresPdf.acento),
      if (concepto.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text('CONCEPTO', style: b.t(8, font: b.r.bold, color: ColoresPdf.gris, spacing: 0.8)),
        for (final x in concepto) pw.Text('• $x', style: b.t(10)),
      ],
      if (p.anulado && p.motivoAnulacion != null) ...[
        pw.SizedBox(height: 8),
        pw.Text('Anulado: ${p.motivoAnulacion}', style: b.t(10, color: ColoresPdf.alerta)),
      ],
      pw.SizedBox(height: 50),
      pw.Row(children: [
        pw.Spacer(),
        pw.Container(
          width: 200,
          padding: const pw.EdgeInsets.only(top: 4),
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: ColoresPdf.tinta))),
          child: pw.Text('Firma', textAlign: pw.TextAlign.center, style: b.t(9, color: ColoresPdf.gris)),
        ),
      ]),
      b.pie(observaciones: p.nota, aviso: 'Recibo de control. La app no cobra ni procesa pagos: solo los registra. No válido como factura.'),
    ],
  );
  return doc.save();
}

/// Nota de pedido al proveedor (el consolidado del día): mismo diseño que la factura.
/// [conPrecios]: agrega el último precio de compra y el total estimado.
Future<Uint8List> pdfConsolidado(Consolidado c, Negocio n, {bool conPrecios = false, Map<String, String?> categorias = const {}}) =>
    pdfPedidoProveedor(c, n, conPrecios: conPrecios, categorias: categorias);

/// Recepción: qué llegó de cada producto y cuánto se pagó.
Future<Uint8List> pdfRecepcion(Consolidado c, Negocio n) async {
  final b = await PdfBase.crear(n);
  final filas = <pw.TableRow>[
    b.filaTitulos(['Producto', 'Pedido', 'Llegó', 'Estado', 'P. compra', 'Subtotal'], derecha: {1, 2, 4, 5}),
  ];
  for (var i = 0; i < c.lineas.length; i++) {
    final l = c.lineas[i];
    final color = switch (l.recepcion) {
      EstadoRecepcion.completo => ColoresPdf.acento,
      EstadoRecepcion.parcial => ColoresPdf.aviso,
      _ => ColoresPdf.alerta,
    };
    filas.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: i.isOdd ? ColoresPdf.fondo : null),
      children: [
        b.celda(l.descripcion),
        b.celda(cantidad(l.cantidad), derecha: true),
        b.celda(cantidad(l.cantidadRecibida), derecha: true, font: b.r.bold),
        b.celda(l.recepcion.texto, color: color, font: b.r.bold, size: 8.5),
        b.celda(l.precioCompra > 0 ? miles(l.precioCompra) : '—', derecha: true),
        b.celda(miles(l.totalCompra), derecha: true, font: b.r.bold),
      ],
    ));
  }
  final parciales = c.lineas.where((l) => l.recepcion == EstadoRecepcion.parcial);
  final doc = b.documento(
    titulo: archivoRecepcion(c),
    contenido: (ctx) => [
      b.encabezado(
        titulo: 'Recepción de mercadería',
        numero: nroDoc(c.numero),
        fecha: c.fechaRecepcion ?? c.fecha,
        extra: [if (c.recibidoPor != null) 'Recibió: ${c.recibidoPor}'],
      ),
      pw.SizedBox(height: 10),
      pw.Text('Proveedor: ${c.proveedorNombre}', style: b.t(12, font: b.r.bold)),
      pw.SizedBox(height: 8),
      pw.Table(
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: ColoresPdf.linea, width: 0.5), bottom: pw.BorderSide(color: ColoresPdf.linea)),
        columnWidths: const {
          0: pw.FlexColumnWidth(4),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1),
          3: pw.FlexColumnWidth(1.6),
          4: pw.FlexColumnWidth(1.4),
          5: pw.FlexColumnWidth(1.5),
        },
        children: filas,
      ),
      pw.Row(children: [
        pw.Spacer(flex: 5),
        pw.Expanded(flex: 4, child: pw.Column(children: [pw.SizedBox(height: 6), b.filaTotal('PAGADO AL PROVEEDOR', gs(c.totalCompra), fuerte: true)])),
      ]),
      if (parciales.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Text('REPARTO DE LO QUE LLEGÓ EN PARTE', style: b.t(9.5, font: b.r.black, color: ColoresPdf.aviso, spacing: 0.5)),
        for (final l in parciales) ...[
          pw.SizedBox(height: 4),
          pw.Text(l.descripcion, style: b.t(9.5, font: b.r.bold)),
          for (final d in l.detalle)
            pw.Text('   ${d.clienteNombre}: ${cantidad(d.asignado ?? 0)} de ${cantidad(d.cantidad)}', style: b.t(9)),
        ],
      ],
      b.pie(aviso: 'Documento de control interno.'),
    ],
  );
  return doc.save();
}

