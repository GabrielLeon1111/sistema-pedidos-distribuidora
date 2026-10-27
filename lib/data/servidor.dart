// =================================================================
//  SERVIDOR (Supabase)
//  Lo único que usan los repositorios para hablar con la base:
//  - Lectura: tablas (con RLS: el vendedor no ve costos ni cobros).
//  - Escritura: siempre por funciones de la base (rpc), que validan
//    permisos y reglas. Las que cambian datos llevan la clave contra
//    duplicados (p_clave): ver 20261023080000_anti_duplicados.sql.
// =================================================================
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/json.dart';

/// Filtro sobre una consulta (eq, gte, etc.).
typedef Filtro = PostgrestFilterBuilder<List<Map<String, dynamic>>> Function(PostgrestFilterBuilder<List<Map<String, dynamic>>> q);

class Servidor {
  /// La base devuelve como máximo 1000 filas por consulta: se piden de a tandas.
  static const _tanda = 1000;

  /// Todas las filas de [tabla] que cumplan [filtro], ordenadas por [orden].
  Future<List<Map<String, dynamic>>> filas(String tabla, {Filtro? filtro, String orden = 'id', bool ascendente = true}) async {
    final r = <Map<String, dynamic>>[];
    for (var desde = 0;; desde += _tanda) {
      var q = supa.from(tabla).select();
      if (filtro != null) q = filtro(q);
      final tanda = await q.order(orden, ascending: ascendente).range(desde, desde + _tanda - 1);
      r.addAll(tanda);
      if (tanda.length < _tanda) return r;
    }
  }

  /// Una fila por id (null si no existe o no la puede ver).
  Future<Map<String, dynamic>?> fila(String tabla, String id, {String columna = 'id'}) =>
      supa.from(tabla).select().eq(columna, id).maybeSingle();

  /// Llama a una función de la base y devuelve lo que contesta.
  Future<dynamic> rpc(String funcion, [Map<String, dynamic>? params]) => supa.rpc(funcion, params: params);

  /// Igual que [rpc] cuando la función devuelve un objeto.
  Future<Map<String, dynamic>> rpcMapa(String funcion, [Map<String, dynamic>? params]) async =>
      Map<String, dynamic>.from(await rpc(funcion, params) as Map);

  /// Igual que [rpc] cuando la función devuelve una lista de objetos.
  Future<List<Map<String, dynamic>>> rpcLista(String funcion, [Map<String, dynamic>? params]) async =>
      toMapList(await rpc(funcion, params));
}
