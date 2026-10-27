import '../data/clave_operacion.dart';
import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/timbrado.dart';
import '../security/registro_seguro.dart';

/// Timbrados de la SET (panel de timbrado).
class TimbradoRepository {
  TimbradoRepository(this._s, this._sesion);
  final Servidor _s;
  final Sesion _sesion;

  // SELECT timbrados (solo el administrador)
  Future<List<Timbrado>> listar() async {
    _sesion.exigirAdmin();
    final filas = await _s.filas('timbrados', orden: 'creado', ascendente: false);
    return [for (final f in filas) Timbrado.fromMap(f)];
  }

  /// El que se usa para facturar hoy (null si no hay ninguno vigente).
  Future<Timbrado?> vigente() async {
    for (final t in await listar()) {
      if (t.activo && t.vigente && !t.agotado) return t;
    }
    return null;
  }

  /// Carga o corrige un timbrado (rpc guardar_timbrado). Al activarlo, los
  /// demás quedan inactivos (se factura con uno solo a la vez).
  Future<Timbrado> guardar(Timbrado t) async {
    _sesion.exigirAdmin();
    validarTimbrado(t);
    return Timbrado.fromMap(await _s.rpcMapa('guardar_timbrado', {'p': t.toMap()}));
  }

  String nuevoId() => nuevaClave();
}

/// Mismas reglas que la base (para avisar antes de enviar).
void validarTimbrado(Timbrado t) {
  if (!RegExp(r'^\d{8}$').hasMatch(t.numero)) throw const ErrorNegocio('El número de timbrado tiene 8 dígitos.');
  if (!RegExp(r'^\d{3}$').hasMatch(t.establecimiento)) throw const ErrorNegocio('El establecimiento tiene 3 dígitos (ej: 001).');
  if (!RegExp(r'^\d{3}$').hasMatch(t.punto)) throw const ErrorNegocio('El punto de expedición tiene 3 dígitos (ej: 001).');
  if (t.fin.isBefore(t.inicio)) throw const ErrorNegocio('La fecha de fin de vigencia tiene que ser después del inicio.');
  if (t.desde < 1 || t.hasta > 9999999 || t.hasta < t.desde) throw const ErrorNegocio('Revisá el rango de numeración (de 1 a 9.999.999).');
  if (t.siguiente < t.desde || t.siguiente > t.hasta + 1) throw const ErrorNegocio('El próximo número tiene que estar dentro del rango.');
  if ((t.pieImprenta ?? '').length > 300) throw const ErrorNegocio('Los datos de la imprenta son muy largos (máximo 300 caracteres).');
}
