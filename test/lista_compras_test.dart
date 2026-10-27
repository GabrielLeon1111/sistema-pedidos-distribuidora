import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sistema_pedidos/models/negocio.dart';
import 'package:sistema_pedidos/models/producto.dart';
import 'package:sistema_pedidos/services/pdf_lista_compras.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es'));

  test('genera la lista de compras agrupada por proveedor, con y sin precios', () async {
    final hoy = DateTime(2026, 10, 23);
    final lineas = [
      LineaCompraLista(Producto(id: 'a', nombre: 'Kitadol Forte', precioVenta: 9500, precioCompra: 7000, iva: 5, creado: hoy), 10, 'Proveedor de Ejemplo S.A.'),
      LineaCompraLista(Producto(id: 'b', nombre: 'Bolígrafo BIC Negro', precioVenta: 1600, creado: hoy), 50, ''),
    ];
    expect(lineas.first.subtotal, 70000);
    const n = Negocio(nombre: 'Distribuidora AM', ciudad: 'Asunción', telefono: '0981 - 000 000');
    expect((await pdfListaCompras(lineas, n, fecha: hoy)).length, greaterThan(1000));
    expect((await pdfListaCompras(lineas, n, conPrecios: false, fecha: hoy)).length, greaterThan(1000));
    expect(archivoListaCompras(hoy), 'Lista_de_compras_2026-10-23.pdf');
  });
}
