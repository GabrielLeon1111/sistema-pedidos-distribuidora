import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../data/local.dart';
import '../data/sesion.dart';
import '../models/usuario.dart';
import '../repositories/usuario_repository.dart';
import '../security/biometria.dart';
import '../security/bloqueo_login.dart';
import '../security/registro_seguro.dart';

enum EstadoSesion { cargando, sinSesion, lista }

/// Sesión de Supabase Auth + la fila de `miembros` (nombre y rol).
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repo, this._sesion, this._local);

  final UsuarioRepository _repo;
  final Sesion _sesion;
  final Local _local;
  StreamSubscription<AuthState>? _sub;

  EstadoSesion _estado = EstadoSesion.cargando;
  EstadoSesion get estado => _estado;

  Usuario? get usuario => _sesion.usuario;
  bool get esAdmin => _sesion.esAdmin;
  String get nombre => usuario?.nombre ?? '';

  /// 5 contraseñas incorrectas seguidas → 30 minutos sin poder intentar.
  final BloqueoLogin bloqueoLogin = BloqueoLogin();

  /// Huella / Face ID.
  final BiometriaService biometria = BiometriaService();
  bool _bloqueado = false;

  /// Hay sesión abierta pero falta la huella / Face ID para entrar.
  bool get bloqueado => _bloqueado;

  bool _recienIngreso = false;

  /// true una sola vez, justo después de entrar con usuario y contraseña
  /// (para ofrecer activar la huella / Face ID).
  bool consumirRecienIngreso() {
    final r = _recienIngreso;
    _recienIngreso = false;
    return r;
  }

  Future<void> iniciar() async {
    _sub = supa.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        _sesion.usuario = null;
        _set(EstadoSesion.sinSesion);
      }
    });
    if (supa.auth.currentSession == null) {
      _set(EstadoSesion.sinSesion);
      return;
    }
    // Con la huella activada, se pide antes de mostrar los datos.
    _bloqueado = await biometria.activada();
    final error = await _cargarMiembro();
    if (error != null) {
      await _cerrar();
      return;
    }
    _set(EstadoSesion.lista);
    notifyListeners();
  }

  /// Lee la fila de `miembros`. Devuelve el mensaje si no puede usar la app.
  Future<String?> _cargarMiembro() async {
    final uid = supa.auth.currentUser?.id;
    try {
      final m = await _repo.miembroActual();
      if (m == null) return 'Tu usuario todavía no está habilitado para usar la app. Pedile acceso al administrador.';
      if (!m.activo) return 'Tu usuario está desactivado. Hablá con el administrador.';
      _sesion.usuario = m;
      if (uid != null) await _local.guardarMiembro(uid, m);
      return null;
    } catch (e) {
      registrarError('cargarMiembro', e);
      // Sin señal: se entra con los datos de la última vez (para levantar pedidos).
      if (esSinConexion(e) && uid != null) {
        final guardado = await _local.miembroGuardado(uid);
        if (guardado != null) {
          _sesion.usuario = guardado;
          return null;
        }
      }
      return mensajeErrorSeguro(e, 'No se pudo abrir tu usuario. Revisá tu conexión e intentá de nuevo.');
    }
  }

  /// Primer uso: crea el administrador (función `usuarios` del servidor) y entra.
  Future<String?> crearPrimerAdmin({required String nombre, required String usuario, required String clave, String? email}) async {
    try {
      await _repo.crearPrimerAdmin(nombre: nombre, usuario: usuario, clave: clave, email: email);
      return await ingresar(email ?? usuario, clave);
    } catch (e) {
      registrarError('primerAdmin', e);
      return mensajeErrorSeguro(e, 'No se pudo crear el administrador. Intentá de nuevo.');
    }
  }

  /// Devuelve null si entró bien, o el mensaje para mostrar.
  /// [usuario]: el email o el usuario del vendedor ("juan.perez").
  Future<String?> ingresar(String usuario, String clave) async {
    // Bloqueada por intentos fallidos: ni se consulta al servidor.
    if (await bloqueoLogin.bloqueadoHasta() != null) return mensajeIntentoFallido(BloqueoLogin.maxIntentos);
    try {
      await _repo.ingresar(usuario, clave);
      await bloqueoLogin.reiniciar();
      final error = await _cargarMiembro();
      if (error != null) {
        await _cerrar();
        return error;
      }
      _bloqueado = false;
      _recienIngreso = true;
      _estado = EstadoSesion.lista;
      // Siempre se avisa: si ya había sesión (entró con contraseña desde la
      // pantalla de la huella), el estado no cambia y no se movía de ahí.
      notifyListeners();
      return null;
    } catch (e) {
      registrarError('ingresar', e);
      // Solo cuenta como intento fallido la contraseña o el usuario incorrecto (no la falta de internet).
      if (esCredencialIncorrecta(e)) return mensajeIntentoFallido(await bloqueoLogin.registrarFallo());
      return mensajeErrorSeguro(e, 'No se pudo iniciar sesión. Intentá de nuevo.');
    }
  }

  Future<void> salir() => _cerrar();

  Future<void> _cerrar() async {
    try {
      await _repo.salir();
    } catch (e) {
      registrarError('salir', e);
    }
    _sesion.usuario = null;
    _bloqueado = false;
    _set(EstadoSesion.sinSesion);
  }

  /// Cuándo se mandó la app al fondo (para no pedir la huella por salir un segundo).
  DateTime? _enFondoDesde;

  void marcarEnFondo() => _enFondoDesde ??= DateTime.now();

  /// Volvió a la app: con la huella activada, se bloquea solo si estuvo en el
  /// fondo más de un minuto (compartir un documento no cuenta).
  Future<void> bloquearSiCorresponde() async {
    final desde = _enFondoDesde;
    _enFondoDesde = null;
    if (desde == null || DateTime.now().difference(desde) < const Duration(minutes: 1)) return;
    if (_estado != EstadoSesion.lista || _bloqueado) return;
    if (await biometria.activada()) {
      _bloqueado = true;
      notifyListeners();
    }
  }

  void desbloquear() {
    if (!_bloqueado) return;
    _bloqueado = false;
    notifyListeners();
  }

  void _set(EstadoSesion e) {
    if (_estado == e) return;
    _estado = e;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
