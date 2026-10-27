// =================================================================
//  ALMACÉN DEL TELÉFONO (para trabajar sin señal)
//  - Cola de lo que todavía no se subió: notas de pedido y locales nuevos.
//  - Copia de locales, productos y pedidos para buscar sin señal.
//  - Bloque de números de pedido reservado (el número es definitivo
//    desde que se levanta la nota).
//  Todo va separado por usuario: si en el teléfono entra otra persona, no
//  ve ni sube lo del anterior.
// =================================================================
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/json.dart';
import '../models/usuario.dart';
import '../security/registro_seguro.dart';
import 'sesion.dart';

class Local {
  Local(this._sesion);
  final Sesion _sesion;
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  String _k(String nombre) => 'u:${_sesion.usuario?.id ?? 'nadie'}:$nombre';

  Future<List<Map<String, dynamic>>> _lista(String nombre) async {
    try {
      final txt = (await _p).getString(_k(nombre));
      return txt == null ? [] : toMapList(jsonDecode(txt));
    } catch (e) {
      registrarError('local_$nombre', e);
      return [];
    }
  }

  Future<void> _guardarLista(String nombre, List<Map<String, dynamic>> filas) async =>
      (await _p).setString(_k(nombre), jsonEncode(filas));

  // ---------------- Copias para buscar sin señal ----------------

  Future<List<Map<String, dynamic>>> copia(String tabla) => _lista('copia_$tabla');
  Future<void> guardarCopia(String tabla, List<Map<String, dynamic>> filas) => _guardarLista('copia_$tabla', filas);

  /// Agrega o actualiza (por id) una fila de la copia.
  Future<void> ponerEnCopia(String tabla, Map<String, dynamic> fila) async {
    final filas = await copia(tabla);
    final i = filas.indexWhere((f) => f['id'] == fila['id']);
    if (i >= 0) {
      filas[i] = fila;
    } else {
      filas.add(fila);
    }
    await guardarCopia(tabla, filas);
  }

  // ---------------- Cola de lo que falta subir ----------------

  Future<List<Map<String, dynamic>>> cola(String tipo) => _lista('cola_$tipo');

  /// Agrega o reemplaza (por id) un elemento de la cola.
  Future<void> ponerEnCola(String tipo, Map<String, dynamic> item) async {
    final filas = await cola(tipo);
    final i = filas.indexWhere((f) => f['id'] == item['id']);
    if (i >= 0) {
      filas[i] = item;
    } else {
      filas.add(item);
    }
    await _guardarLista('cola_$tipo', filas);
  }

  Future<void> quitarDeCola(String tipo, String id) async {
    final filas = await cola(tipo);
    filas.removeWhere((f) => f['id'] == id);
    await _guardarLista('cola_$tipo', filas);
  }

  Future<int> cantidadEnCola() async => (await cola('pedidos')).length + (await cola('clientes')).length;

  // ---------------- Números de pedido reservados ----------------

  /// Rangos [siguiente, hasta] que quedan del bloque reservado.
  Future<List<List<int>>> _rangos() async => [
        for (final r in await _lista('numeros')) [toInt(r['siguiente']), toInt(r['hasta'])],
      ];

  Future<int> numerosDisponibles() async => (await _rangos()).fold<int>(0, (s, r) => s + (r[1] - r[0] + 1));

  Future<void> agregarNumeros(int desde, int hasta) async {
    final rangos = await _rangos()..add([desde, hasta]);
    await _guardarLista('numeros', [for (final r in rangos) {'siguiente': r[0], 'hasta': r[1]}]);
  }

  /// El próximo número de pedido (null si no queda ninguno).
  Future<int?> tomarNumero() async {
    final rangos = await _rangos();
    if (rangos.isEmpty) return null;
    final n = rangos.first[0];
    rangos.first[0]++;
    if (rangos.first[0] > rangos.first[1]) rangos.removeAt(0);
    await _guardarLista('numeros', [for (final r in rangos) {'siguiente': r[0], 'hasta': r[1]}]);
    return n;
  }

  // ---------------- Usuario (para abrir la app sin señal) ----------------

  Future<void> guardarMiembro(String userId, Usuario u) async => (await _p).setString('miembro:$userId', jsonEncode({
        'id': u.id,
        'nombre': u.nombre,
        'usuario': u.usuario,
        'rol': u.rol,
        'activo': u.activo,
        'creado': u.creado.toIso8601String(),
      }));

  Future<Usuario?> miembroGuardado(String userId) async {
    try {
      final txt = (await _p).getString('miembro:$userId');
      return txt == null ? null : Usuario.fromMap(Map<String, dynamic>.from(jsonDecode(txt) as Map));
    } catch (_) {
      return null;
    }
  }
}
