import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_pedidos/data/clave_operacion.dart';
import 'package:sistema_pedidos/models/pedido.dart';
import 'package:sistema_pedidos/models/venta.dart';
import 'package:sistema_pedidos/repositories/usuario_repository.dart';
import 'package:sistema_pedidos/security/registro_seguro.dart';

// El circuito completo (pedido → consolidado → recepción → entrega → cobro,
// anti-duplicados y permisos) se prueba contra la base real con
// supabase/tests/circuito.sql. Acá va lo que hace la app por su cuenta.
void main() {
  group('clave contra duplicados', () {
    test('se repite en cada reintento y cambia después de un éxito', () {
      final c = ClaveOperacion();
      final primera = c.valor;
      expect(c.valor, primera);
      c.renovar();
      expect(c.valor, isNot(primera));
    });

    test('cada clave nueva es distinta', () {
      expect(nuevaClave(), isNot(nuevaClave()));
    });
  });

  test('se entra con el email o con el usuario', () {
    expect(emailDeUsuario('Admin@Gmail.com '), 'admin@gmail.com');
    expect(emailDeUsuario('juan.perez'), 'juan.perez@$dominioUsuarios');
  });

  group('errores para el usuario', () {
    test('muestra los mensajes escritos en la base y oculta los técnicos', () {
      expect(mensajeErrorSeguro(const PostgrestException(message: 'Elegí el local.', code: 'P0001')), 'Elegí el local.');
      expect(
        mensajeErrorSeguro(const PostgrestException(message: 'duplicate key value violates unique constraint "clientes_nombre_unico"', code: '23505')),
        'Ya existe un local con ese nombre. Buscalo en la lista.',
      );
      expect(mensajeErrorSeguro(const PostgrestException(message: 'select * from secreta', code: 'XX000'), 'Genérico'), 'Genérico');
      expect(mensajeErrorSeguro(const FunctionException(status: 409, details: {'error': 'Ya existe un usuario "juan".'})), 'Ya existe un usuario "juan".');
      expect(mensajeErrorSeguro(const ErrorNegocio('Revisá el monto.')), 'Revisá el monto.');
      expect(mensajeErrorSeguro(const SocketException('sin red')), contains('No hay conexión'));
    });

    test('distingue un rechazo seguro de un corte (que pudo haber entrado)', () {
      expect(esRechazoDelServidor(const PostgrestException(message: 'x', code: 'P0001')), isTrue);
      expect(esRechazoDelServidor(const PostgrestException(message: 'Bad gateway', code: '502')), isFalse);
      expect(esRechazoDelServidor(const SocketException('sin red')), isFalse);
      expect(esSinConexion(const SocketException('sin red')), isTrue);
    });
  });

  group('los modelos leen lo que devuelve la base', () {
    test('venta con su factura (to_jsonb de la fila)', () {
      final v = Venta.fromMap({
        'id': 'v1',
        'numero': 12,
        'fecha': '2026-10-23T15:04:05.123456+00:00',
        'cliente_id': 'c1',
        'cliente': {'nombre': 'Despensa Uno', 'ruc': '1234567-8'},
        'lineas': [
          {'id': 'l1', 'descripcion': 'Aceite', 'cantidad': 5.000, 'precio': 15000, 'iva': 10, 'estado': 'llego', 'costo': 12000},
        ],
        'total': 75000,
        'costo_total': 60000,
        'pagado': 30000,
        'anulada': false,
        'entrega_parcial': false,
        'timbrado_id': 't1',
        'timbrado_numero': '12345678',
        'timbrado_inicio': '2026-08-10',
        'timbrado_fin': '2027-08-31',
        'establecimiento': '001',
        'punto': '001',
        'factura_numero': 1481,
        'condicion': 'credito',
        'factura_pie': 'Imprenta',
      });
      expect(v.saldo, 45000);
      expect(v.factura!.numeroCompleto, '001-001 0001481');
      expect(v.factura!.pieImprenta, 'Imprenta');
      expect(v.cliente.nombre, 'Despensa Uno');
    });

    test('pedido del vendedor (sin costos)', () {
      final p = Pedido.fromMap({
        'id': 'p1',
        'numero': 3,
        'fecha': '2026-10-23T12:00:00+00:00',
        'cliente_id': 'c1',
        'cliente': {'nombre': 'Despensa Uno'},
        'lineas': [
          {'id': 'l1', 'descripcion': 'Aceite', 'cantidad': 6, 'precio': 15000, 'estado': 'pendiente'},
        ],
        'estado': 'cargado',
        'actualizado': '2026-10-23T12:00:00+00:00',
      });
      expect(p.total, 90000);
      expect(p.estado, EstadoPedido.cargado);
      expect(p.lineas.single.costo, 0);
    });
  });
}
