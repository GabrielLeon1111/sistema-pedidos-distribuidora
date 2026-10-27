import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_pedidos/data/servidor.dart';
import 'package:sistema_pedidos/data/sesion.dart';
import 'package:sistema_pedidos/models/negocio.dart';
import 'package:sistema_pedidos/providers/negocio_provider.dart';
import 'package:sistema_pedidos/repositories/negocio_repository.dart';
import 'package:sistema_pedidos/widgets/encabezado_negocio.dart';
import 'package:sistema_pedidos/widgets/marca.dart';

class _ServidorEncabezado extends Servidor {
  bool enLinea = false;
  Completer<Map<String, dynamic>?>? pendiente;

  @override
  Future<dynamic> rpc(String funcion, [Map<String, dynamic>? params]) async {
    if (funcion != 'encabezado_negocio') throw StateError(funcion);
    if (pendiente != null) return pendiente!.future;
    if (!enLinea) throw const SocketException('sin señal');
    return {...const Negocio(nombre: 'Distribuidora AM').toMap(), 'tiene_admin': true};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sin copia no muestra nombre ficticio y recupera nombre cuando vuelve señal', (tester) async {
    final servidor = _ServidorEncabezado();
    final negocio = NegocioProvider(NegocioRepository(servidor, Sesion()));
    addTearDown(negocio.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: negocio,
        child: const MaterialApp(
          home: Scaffold(body: Column(children: [EncabezadoNegocio(soloNombre: true), Marca()])),
        ),
      ),
    );
    unawaited(negocio.restaurar());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(negocio.listo, isFalse, reason: 'Sin datos reales el encabezado sigue oculto, aunque pase tiempo.');
    expect(tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity)).map((w) => w.opacity), everyElement(0));

    servidor.enLinea = true;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(negocio.negocio.nombre, 'Distribuidora AM');
    expect(negocio.listo, isTrue);
    expect(negocio.tieneAdmin, isTrue);
    expect(tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity)).map((w) => w.opacity), everyElement(1));
    final copia = (await SharedPreferences.getInstance()).getString('negocio_encabezado');
    expect(jsonDecode(copia!)['nombre'], 'Distribuidora AM');
  });

  testWidgets('con copia muestra nombre real sin señal', (tester) async {
    SharedPreferences.setMockInitialValues({'negocio_encabezado': jsonEncode(const Negocio(nombre: 'Distribuidora AM').toMap())});
    final negocio = NegocioProvider(NegocioRepository(_ServidorEncabezado(), Sesion()));
    addTearDown(negocio.dispose);
    unawaited(negocio.restaurar());
    await tester.pump();
    expect(negocio.listo, isTrue);
    expect(negocio.negocio.nombre, 'Distribuidora AM');
  });

  testWidgets('dispose cancela reintentos y descarta respuesta pendiente', (tester) async {
    final servidor = _ServidorEncabezado()..pendiente = Completer<Map<String, dynamic>?>();
    final negocio = NegocioProvider(NegocioRepository(servidor, Sesion()));
    unawaited(negocio.restaurar());
    await tester.pump();
    negocio.dispose();
    servidor.pendiente!.complete({...const Negocio(nombre: 'Distribuidora AM').toMap(), 'tiene_admin': true});
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
  });
}
