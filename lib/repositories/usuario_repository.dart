import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/usuario.dart';
import '../security/claves.dart';
import '../security/registro_seguro.dart';
import '../utils/validacion.dart';

/// Los vendedores entran con un usuario (ej: "juan.perez"). Por dentro se usa
/// un email con un dominio reservado que nunca recibe correos (.invalid);
/// es el mismo que usa la función `usuarios` del servidor.
const dominioUsuarios = 'usuarios.sistema-pedidos.invalid';

/// Lo que escribe la persona al entrar: su email, o su usuario.
String emailDeUsuario(String entrada) {
  final e = entrada.trim().toLowerCase();
  return e.contains('@') ? e : '$e@$dominioUsuarios';
}

/// Usuarios de la app: Supabase Auth + tabla `miembros` (nombre y rol), y la
/// función `usuarios` del servidor para que el administrador maneje a los
/// vendedores (necesita la clave de servicio, que no está en la app).
class UsuarioRepository {
  UsuarioRepository(this._s, this._sesion);
  final Servidor _s;
  final Sesion _sesion;

  static final _formatoUsuario = RegExp(r'^[a-z0-9._-]{3,30}$');

  Usuario? get usuarioActual => _sesion.usuario;

  static Usuario _deMiembro(Map<String, dynamic> m) => Usuario.fromMap({...m, 'id': m['user_id']});

  /// La fila de `miembros` de quien tiene la sesión abierta (null si no está habilitado).
  Future<Usuario?> miembroActual() async {
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return null;
    final f = await _s.fila('miembros', uid, columna: 'user_id');
    return f == null ? null : _deMiembro(f);
  }

  /// Entra con email (o usuario) y contraseña.
  Future<void> ingresar(String usuario, String clave) =>
      supa.auth.signInWithPassword(email: emailDeUsuario(usuario), password: clave);

  Future<void> salir() => supa.auth.signOut();

  /// Primer uso: crea el administrador y el proveedor principal (función `usuarios`).
  Future<void> crearPrimerAdmin({required String nombre, required String usuario, required String clave, String? email}) =>
      _funcion({'accion': 'primer_admin', 'nombre': nombre, 'usuario': usuario.trim().toLowerCase(), 'clave': clave, 'email': email});

  // SELECT miembros (el administrador ve todos)
  Future<List<Usuario>> listar() async {
    _sesion.exigirAdmin();
    return [for (final f in await _s.filas('miembros', orden: 'nombre')) _deMiembro(f)];
  }

  Future<void> crear({required String nombre, required String usuario, required String clave, String rol = 'vendedor'}) async {
    _sesion.exigirAdmin();
    final n = limpiarTexto(nombre);
    final login = usuario.trim().toLowerCase();
    if (n.length < 3) throw const ErrorNegocio('Escribí el nombre y apellido.');
    if (!_formatoUsuario.hasMatch(login)) {
      throw const ErrorNegocio('El usuario solo puede tener letras, números, punto o guion (ej: juan.perez).');
    }
    final err = validarClave(clave);
    if (err != null) throw ErrorNegocio(err);
    await _funcion({'accion': 'crear', 'nombre': n, 'usuario': login, 'clave': clave, 'rol': rol});
  }

  Future<void> activar(String id, bool activo) async {
    final yo = _sesion.exigirAdmin();
    if (id == yo.id && !activo) throw const ErrorNegocio('No podés desactivar tu propio usuario.');
    await _funcion({'accion': 'activar', 'user_id': id, 'activo': activo});
  }

  /// El administrador le pone una contraseña nueva a otro usuario.
  Future<void> cambiarClave(String id, String clave) async {
    final yo = _sesion.exigirAdmin();
    final err = validarClave(clave);
    if (err != null) throw ErrorNegocio(err);
    if (id == yo.id) throw const ErrorNegocio('Tu propia contraseña cambiala desde "Mi cuenta".');
    await _funcion({'accion': 'clave', 'user_id': id, 'clave': clave});
  }

  /// Cambiar la propia contraseña (pide la actual).
  Future<void> cambiarMiClave(String actual, String nueva) async {
    _sesion.exigirUsuario();
    final email = supa.auth.currentUser?.email;
    if (email == null) throw const SinPermiso('Tu sesión se cerró. Volvé a ingresar.');
    final err = validarClave(nueva);
    if (err != null) throw ErrorNegocio(err);
    try {
      await supa.auth.signInWithPassword(email: email, password: actual);
    } on AuthException catch (e) {
      if (esCredencialIncorrecta(e)) throw const ErrorNegocio('La contraseña actual no es correcta.');
      rethrow;
    }
    await supa.auth.updateUser(UserAttributes(password: nueva));
  }

  Future<void> _funcion(Map<String, dynamic> body) async {
    await supa.functions.invoke('usuarios', body: {for (final e in body.entries) if (e.value != null) e.key: e.value});
  }
}
