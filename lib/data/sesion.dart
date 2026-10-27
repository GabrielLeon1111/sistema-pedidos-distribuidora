import '../models/usuario.dart';
import '../security/registro_seguro.dart';

/// Quién está usando la app (lo pone el AuthProvider al ingresar).
///
/// Solo ordena las pantallas y corta antes de llamar al servidor: la base
/// vuelve a verificar el permiso en cada operación (assert_admin).
class Sesion {
  Usuario? usuario;

  bool get esAdmin => usuario?.esAdmin ?? false;

  Usuario exigirUsuario() {
    final u = usuario;
    if (u == null) throw const SinPermiso('Tu sesión se cerró. Volvé a ingresar.');
    return u;
  }

  Usuario exigirAdmin() {
    final u = exigirUsuario();
    if (!u.esAdmin) throw const SinPermiso();
    return u;
  }
}
