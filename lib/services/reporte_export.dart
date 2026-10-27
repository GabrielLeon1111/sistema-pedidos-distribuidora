import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/negocio.dart';
import '../models/reportes.dart';
import '../models/venta.dart';
import '../utils/formato.dart';
import 'pdf_base.dart';
import 'pdf_fuentes.dart';

String nombreReporte(Reporte r, String ext) =>
    'Reporte_${fechaCorta.format(r.desde).replaceAll('/', '-')}_al_${fechaCorta.format(r.hasta).replaceAll('/', '-')}.$ext';

String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} %';

Future<Uint8List> reportePdf(Reporte r, Negocio n) async {
  final b = await PdfBase.crear(n);
  pw.Widget kpi(String label, int valor, {bool destacado = false}) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6, bottom: 6),
          padding: const pw.EdgeInsets.all(7),
          decoration: pw.BoxDecoration(
            color: destacado ? ColoresPdf.acentoSuave : PdfColors.white,
            border: pw.Border.all(color: destacado ? ColoresPdf.acento : ColoresPdf.linea),
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label.toUpperCase(), style: b.t(7, font: b.r.bold, color: ColoresPdf.gris, spacing: 0.5)),
            pw.SizedBox(height: 2),
            pw.Text(gs(valor), style: b.t(11.5, font: b.r.black, color: ColoresPdf.tinta)),
          ]),
        ),
      );
  pw.Widget tabla(List<String> titulos, List<List<String>> filas, {Set<int> derecha = const {}}) => pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: ColoresPdf.linea, width: 0.5),
        headerStyle: b.t(8.5, font: b.r.bold, color: ColoresPdf.tinta),
        headerDecoration: const pw.BoxDecoration(color: ColoresPdf.acentoSuave),
        cellStyle: b.t(8.5),
        cellAlignments: {for (final i in derecha) i: pw.Alignment.centerRight},
        headers: titulos,
        data: filas,
      );
  pw.Widget titulo(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
        child: pw.Text(s.toUpperCase(), style: b.t(9.5, font: b.r.black, color: ColoresPdf.acento, spacing: 0.6)),
      );

  final doc = b.documento(
    titulo: nombreReporte(r, 'pdf'),
    contenido: (c) => [
      b.encabezado(titulo: 'Reporte', numero: '${fechaCorta.format(r.desde)} al ${fechaCorta.format(r.hasta)}', fecha: DateTime.now()),
      pw.SizedBox(height: 10),
      pw.Row(children: [kpi('Vendido', r.vendido), kpi('Costo de lo vendido', r.costoVendido), kpi('Ganancia', r.ganancia)]),
      pw.Row(children: [kpi('Gastos', r.gastos), kpi('Pérdidas', r.perdidas), kpi('Ganancia real', r.gananciaReal, destacado: true)]),
      pw.Row(children: [
        kpi('Pagado al proveedor', r.totalPagadoProveedores),
        kpi('Cobrado', r.cobrado),
        kpi('Falta cobrar', r.faltaCobrar),
        kpi('Perdido por rechazos', r.perdidoRechazos),
      ]),
      pw.Text(
        '${r.notas} facturas · margen ${_pct(r.margen)} · ${r.cantidadRechazos} rechazos'
        '${r.descuentos > 0 ? ' · descuentos ${gs(r.descuentos)}' : ''} · ganancia real = ganancia − gastos − pérdidas',
        style: b.t(8.5, color: ColoresPdf.gris),
      ),
      titulo('Ganancia y margen por producto'),
      tabla(
        ['Producto', 'Cantidad', 'Vendido', 'Ganancia', 'Margen'],
        [for (final p in r.productos) [p.nombre, cantidad(p.cantidad), miles(p.vendido), miles(p.ganancia), _pct(p.margen)]],
        derecha: {1, 2, 3, 4},
      ),
      titulo('Por local'),
      tabla(
        ['Local', 'Vendido', 'Ganancia', 'Margen', 'Cobrado', 'Debe', 'Rechazos'],
        [for (final l in r.locales) [l.nombre, miles(l.vendido), miles(l.ganancia), _pct(l.margen), miles(l.cobrado), miles(l.saldo), '${l.rechazos}']],
        derecha: {1, 2, 3, 4, 5, 6},
      ),
      if (r.gastosPorCategoria.isNotEmpty) ...[
        titulo('Gastos por categoría'),
        tabla(['Categoría', 'Cantidad', 'Monto'], [for (final g in r.gastosPorCategoria) [g.categoria, '${g.cantidad}', miles(g.monto)]], derecha: {1, 2}),
      ],
    ],
  );
  return doc.save();
}

Uint8List reporteExcel(Reporte r, List<Venta> ventas) {
  final book = xls.Excel.createExcel();
  final negrita = xls.CellStyle(bold: true);
  xls.CellValue txt(String s) => xls.TextCellValue(s);
  xls.CellValue num_(num n) => n is int ? xls.IntCellValue(n) : xls.DoubleCellValue(n.toDouble());
  void encabezado(xls.Sheet h, List<String> cols) {
    h.appendRow(cols.map(txt).toList());
    for (var i = 0; i < cols.length; i++) {
      h.cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: h.maxRows - 1)).cellStyle = negrita;
    }
  }

  final res = book['Resumen'];
  for (final (k, v) in [
    ('Período', '${fechaCorta.format(r.desde)} al ${fechaCorta.format(r.hasta)}'),
  ]) {
    res.appendRow([txt(k), txt(v)]);
  }
  for (final (k, v) in [
    ('Vendido', r.vendido),
    ('Costo de lo vendido', r.costoVendido),
    ('Ganancia', r.ganancia),
    ('Gastos', r.gastos),
    ('Pérdidas', r.perdidas),
    ('Ganancia real', r.gananciaReal),
    ('Pagado al proveedor (recepciones)', r.pagadoProveedor),
    ('Compras propias', r.comprasPropias),
    ('Cobrado', r.cobrado),
    ('Falta cobrar', r.faltaCobrar),
    ('Perdido por rechazos', r.perdidoRechazos),
    ('Cantidad de rechazos', r.cantidadRechazos),
    ('Facturas', r.notas),
  ]) {
    res.appendRow([txt(k), num_(v)]);
  }

  final prod = book['Productos'];
  encabezado(prod, ['Producto', 'Unidad', 'Cantidad', 'Vendido', 'Ganancia', 'Margen %']);
  for (final p in r.productos) {
    prod.appendRow([txt(p.nombre), txt(p.unidad), num_(p.cantidad), num_(p.vendido), num_(p.ganancia), num_(double.parse((p.margen ?? 0).toStringAsFixed(1)))]);
  }

  final loc = book['Locales'];
  encabezado(loc, ['Local', 'Vendido', 'Ganancia', 'Margen %', 'Cobrado', 'Debe', 'Rechazos']);
  for (final l in r.locales) {
    loc.appendRow([txt(l.nombre), num_(l.vendido), num_(l.ganancia), num_(double.parse((l.margen ?? 0).toStringAsFixed(1))), num_(l.cobrado), num_(l.saldo), num_(l.rechazos)]);
  }

  final fac = book['Facturas'];
  encabezado(fac, ['Factura', 'Fecha', 'Local', 'RUC', 'Condición', 'Total', 'Costo', 'Ganancia', 'Pagado', 'Saldo', 'Estado']);
  for (final v in ventas) {
    fac.appendRow([
      txt(v.factura?.numeroCompleto ?? nroDoc(v.numero)),
      txt(fechaHora.format(v.fecha)),
      txt(v.cliente.nombre),
      txt(v.cliente.ruc ?? ''),
      txt(v.factura == null ? '' : (v.factura!.contado ? 'Contado' : 'Crédito')),
      num_(v.total),
      num_(v.costoTotal),
      num_(v.ganancia),
      num_(v.pagado),
      num_(v.saldo),
      txt(v.anulada ? 'Anulada' : v.estadoPago.texto),
    ]);
  }

  if (r.gastosPorCategoria.isNotEmpty) {
    final g = book['Gastos'];
    encabezado(g, ['Categoría', 'Cantidad', 'Monto']);
    for (final x in r.gastosPorCategoria) {
      g.appendRow([txt(x.categoria), num_(x.cantidad), num_(x.monto)]);
    }
  }
  book.delete('Sheet1');
  book.setDefaultSheet('Resumen');
  return Uint8List.fromList(book.encode()!);
}
