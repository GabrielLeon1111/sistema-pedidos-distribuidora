import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sistema_pedidos/models/consolidado.dart';
import 'package:sistema_pedidos/models/negocio.dart';
import 'package:sistema_pedidos/services/pdf_documentos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es'));

  test('genera la hoja consolidada para el proveedor, con y sin precios', () async {
    DetalleLocal d(int pedido, String local, double cant, {String? nota}) =>
        DetalleLocal(pedidoId: 'p$pedido', pedidoNumero: pedido, lineaId: 'l$pedido', clienteNombre: local, cantidad: cant, nota: nota);
    LineaConsolidado l(String desc, List<DetalleLocal> det, {String? codigo, int precio = 0, String? nota}) => LineaConsolidado(
          nota: nota,
          codigo: codigo,
          precioCompra: precio,
          descripcion: desc,
          unidad: 'unidad',
          cantidad: det.fold(0, (s, x) => s + x.cantidad),
          detalle: det,
        );
    final c = Consolidado(
      id: 'c1',
      numero: 3,
      fecha: DateTime(2026, 10, 24, 18, 30),
      proveedorId: 'prov',
      proveedorNombre: 'Proveedor de Ejemplo S.A.',
      proveedorTelefono: '0981 222 333',
      pedidoIds: const ['p4', 'p5', 'p6'],
      creadoPor: 'Juan Benítez',
      lineas: [
        l('Kitadol Forte', [d(4, 'Desp La Familia', 10), d(5, 'Despensa San Roque', 6)], precio: 7000),
        l('Ergo Dolanet', [d(4, 'Desp La Familia', 24)], precio: 5500),
        l('Mentovick Ungüento', [d(5, 'Despensa San Roque', 12), d(6, 'Almacén Doña Rosa', 18)], precio: 2400),
        l('Novalgina Gota', [d(6, 'Almacén Doña Rosa', 3)], precio: 18500),
        l('Linterna LED Mediano', [d(4, 'Desp La Familia', 6), d(6, 'Almacén Doña Rosa', 2)], precio: 13000),
        l('Bolígrafo BIC Negro', [d(5, 'Despensa San Roque', 50)], precio: 1100),
        l('Tinte para cabello NANTYR', [d(4, 'Desp La Familia', 3, nota: '1 rubio, 2 negros'), d(6, 'Almacén Doña Rosa', 2, nota: '2 castaños')],
            precio: 8500, nota: '1 rubio, 2 negros · 2 castaños'),
      ],
    );
    const n = Negocio(
      nombre: 'Distribuidora AM',
      propietario: 'Juan Carlos Benítez',
      actividades: 'Comercio al por menor de cosméticos y artículos de tocador - Bazar - Comercio de artículos de ferretería',
      direccion: 'Calle Principal 123 - Barrio Centro',
      ruc: '4501238-7',
      telefono: '0981 - 000 000',
      ciudad: 'Asunción',
    );
    final sin = await pdfConsolidado(c, n);
    final precios = await pdfConsolidado(c, n, conPrecios: true);
    expect(precios.length, greaterThan(1000));
    expect(sin.length, greaterThan(1000));
    final carpeta = Platform.environment['CONSOLIDADO_DIR'];
    if (carpeta != null) {
      File('$carpeta/consolidado.pdf').writeAsBytesSync(sin);
      File('$carpeta/consolidado_precios.pdf').writeAsBytesSync(precios);
    }
  });
}
