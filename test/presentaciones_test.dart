import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_pedidos/models/ganancia.dart';
import 'package:sistema_pedidos/models/linea.dart';
import 'package:sistema_pedidos/models/producto.dart';
import 'package:sistema_pedidos/utils/formato.dart';

void main() {
  final zapatilla = Producto.fromMap({
    'id': 'p1',
    'nombre': 'Zapatilla havaiana clásica 34/39',
    'unidad': 'unidad',
    'precio_venta': 36000,
    'precio_compra': 29000,
    'stock': 30,
    'presentaciones': [
      {'nombre': 'docena', 'unidades': 12, 'precio': 430500},
    ],
    'creado': '2026-10-25T00:00:00Z',
  });

  test('el producto ofrece la unidad y la docena con sus precios', () {
    expect(zapatilla.formasDeVenta.map((f) => f.nombre), ['unidad', 'docena']);
    expect(zapatilla.forma('docena').unidades, 12);
    expect(zapatilla.forma('docena').precio, 430500);
    expect(zapatilla.forma(null).precio, 36000);
    expect(zapatilla.forma('caja').nombre, 'unidad', reason: 'Una forma que no existe vuelve a la unidad');
    expect(zapatilla.textoPrecios, contains('430.500 docena'));
    expect(Producto.fromMap(zapatilla.toMap()).presentaciones.single.unidades, 12, reason: 'Se guarda en la copia del teléfono');
  });

  test('una línea por docena cobra por docena y mueve 12 del stock', () {
    final l = Linea.fromMap({
      'id': 'l1',
      'descripcion': zapatilla.nombre,
      'unidad': 'docena',
      'factor': 12,
      'cantidad': 2,
      'precio': 430500,
      'costo': 348000,
    });
    expect(l.total, 861000);
    expect(l.cantidadEnStock, 24);
    expect(l.ganancia, 861000 - 696000);
    expect(l.unidadTexto(), 'docenas');
    expect(Linea.fromMap(l.toMap()).factor, 12);
    expect(Linea.fromMap({...l.toMap(), 'nota': '1 rubio, 2 negros'}).nota, '1 rubio, 2 negros');
    expect(Linea.fromMap({...l.toMap(), 'nota': '  '}).nota, isNull, reason: 'Un detalle en blanco no se guarda');
    expect(Linea.fromMap({'id': 'x', 'descripcion': 'Viejo', 'cantidad': 1, 'precio': 1}).factor, 1,
        reason: 'Las líneas de antes no traen factor');
  });

  test('las formas sin nombre de cantidad dicen cuántas traen', () {
    expect(textoForma('paquete', 12, 2), 'paquetes de 12');
    expect(textoForma('caja', 24, 1), 'caja de 24');
    expect(textoForma('docena', 12, 3), 'docenas');
    expect(textoForma('unidad', 1, 5), 'unidades');
    expect(textoForma('par', 1, 2), 'pares');
  });

  test('ganancia aproximada de la nota: con el último precio de compra o el costo que llegó', () {
    final docena = Linea(id: 'a', productoId: 'p1', descripcion: 'Zapatilla', unidad: 'docena', factor: 12, cantidad: 2, precio: 430500);
    final sinPrecio = Linea(id: 'b', descripcion: 'Producto nuevo', cantidad: 1, precio: 5000);
    final e = EstimacionGanancia.de([docena, sinPrecio], [zapatilla]);
    expect(e.venta, 861000, reason: 'Solo cuenta lo que tiene costo');
    expect(e.costo, 2 * 12 * 29000);
    expect(e.ganancia, 861000 - 696000);
    expect(e.sinCosto, ['Producto nuevo']);
    // Al recibir se pone lo que se pagó de verdad.
    expect(EstimacionGanancia.de([docena], [zapatilla], costos: {'a': 360000}).ganancia, 861000 - 720000);
  });
}
