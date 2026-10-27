import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/negocio.dart';

class NegocioRepository {
  NegocioRepository(this._s, this._sesion);
  final Servidor _s;
  final Sesion _sesion;

  // SELECT negocio (una sola fila, la ven todos los usuarios)
  Future<Negocio> obtener() async {
    final f = await _s.fila('negocio', 'negocio');
    return f == null ? const Negocio() : Negocio.fromMap(f);
  }

  /// Solo lo que sale impreso en la factura (rpc encabezado_negocio): se puede
  /// leer sin sesión, para la pantalla de ingreso.
  Future<Map<String, dynamic>?> encabezado() async {
    final r = await _s.rpc('encabezado_negocio');
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  // rpc guardar_negocio (solo el administrador)
  Future<void> guardar(Negocio n) async {
    _sesion.exigirAdmin();
    await _s.rpc('guardar_negocio', {'p': n.toMap()});
  }
}
