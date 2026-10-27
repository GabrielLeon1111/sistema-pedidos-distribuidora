import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Clave contra duplicados de una operación (ver `reservar_clave` en
/// supabase/migrations/20261023080000_anti_duplicados.sql).
///
/// Se crea al abrir el formulario y se repite en cada reintento: si el primer
/// envío sí había entrado, la base devuelve ese resultado en vez de hacerlo
/// dos veces. Cuando la operación sale bien se [renovar], así la próxima
/// (otro cobro en la misma pantalla, por ejemplo) es una operación nueva.
class ClaveOperacion {
  String _valor = _uuid.v4();

  String get valor => _valor;

  void renovar() => _valor = _uuid.v4();
}

/// Clave nueva para una operación de un solo uso.
String nuevaClave() => _uuid.v4();
