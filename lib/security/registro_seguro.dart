// =================================================================
//  ERRORES SEGUROS
//  Dos funciones para manejar errores sin filtrar datos personales:
//    - registrarError: deja un rastro en la consola de desarrollo.
//    - mensajeErrorSeguro: decide qué texto ve el usuario en pantalla.
//  Regla de oro: NUNCA mostrar ni imprimir la respuesta cruda del servidor.
// =================================================================
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error de una regla del negocio (stock, estados, permisos…) que se detecta
/// en la app antes de llamar al servidor. Su mensaje está escrito para el
/// usuario y se puede mostrar tal cual.
class ErrorNegocio implements Exception {
  const ErrorNegocio(this.mensaje);
  final String mensaje;

  @override
  String toString() => 'ErrorNegocio';
}

/// El usuario no tiene permiso para esta operación.
class SinPermiso extends ErrorNegocio {
  const SinPermiso([super.mensaje = 'Tu usuario no tiene permiso para hacer esto.']);
}

// REGISTRAR UN ERROR (solo para el programador). Imprime dónde pasó y de qué
// TIPO fue, pero nunca el mensaje completo. En release no registra nada.
void registrarError(String contexto, Object error) {
  if (kReleaseMode) return;
  final codigo = switch (error) {
    PostgrestException e => ' code=${e.code}',
    FunctionException e => ' status=${e.status}',
    _ => '',
  };
  debugPrint('$contexto [${error.runtimeType}$codigo]');
}

/// Usuario o contraseña incorrectos (cuenta para el bloqueo por intentos).
bool esCredencialIncorrecta(Object error) =>
    error is AuthException && (error.code == 'invalid_credentials' || error.message.toLowerCase().contains('invalid login'));

/// El servidor contestó con un error (stock, datos, permisos...): la operación
/// seguro NO se hizo. Un 5xx sin código de la base (502, 504: se cayó la
/// conexión en el medio) no cuenta: la operación pudo haber entrado, y se
/// reintenta con la misma clave (ver ClaveOperacion).
bool esRechazoDelServidor(Object error) {
  if (error is ErrorNegocio) return true;
  if (error is! PostgrestException) return false;
  final code = error.code ?? '';
  return code.isNotEmpty && !RegExp(r'^5\d\d$').hasMatch(code);
}

/// No hubo respuesta del servidor (sin señal, se cortó, tardó demasiado).
bool esSinConexion(Object error) {
  if (error is SocketException || error is TimeoutException || error is HttpException) return true;
  if (error is AuthRetryableFetchException) return true;
  final tipo = error.runtimeType.toString();
  return tipo.contains('ClientException') || tipo.contains('Socket');
}

// ELEGIR EL TEXTO PARA EL USUARIO. Recibe el error y un mensaje genérico.
String mensajeErrorSeguro(Object error, [String generico = 'No se pudo completar la operación. Intentá de nuevo.']) {
  if (error is ErrorNegocio) return error.mensaje;
  if (error is PostgrestException) {
    switch (error.code) {
      // Mensajes escritos por nosotros en las funciones de la base (raise exception).
      case 'P0001':
        return error.message;
      case '23505':
        if (error.message.contains('clientes_nombre_unico')) return 'Ya existe un local con ese nombre. Buscalo en la lista.';
        if (error.message.contains('productos_nombre_unico')) return 'Ya existe un producto con ese nombre. Buscalo en la lista.';
        if (error.message.contains('productos_codigo_unico')) return 'Ese código ya es de otro producto.';
        return 'Ya existe un registro con ese mismo dato.';
      case '23503':
        return 'No se puede borrar porque tiene documentos registrados. Podés desactivarlo.';
      case '23514':
        return 'Hay un dato que no es válido. Revisá los campos.';
      case '42501':
        // assert_miembro / assert_admin traen su propio mensaje.
        return error.message.startsWith('Tu usuario') ? error.message : 'Tu usuario no tiene permiso para hacer esto.';
      case 'PGRST301':
      case 'PGRST303':
        return 'Tu sesión venció. Volvé a iniciar sesión.';
    }
    return generico;
  }
  if (error is FunctionException) {
    // La función `usuarios` contesta {error: "..."} con textos escritos para el usuario.
    final d = error.details;
    if (d is Map && d['error'] is String) return d['error'] as String;
    if (error.status == 401) return 'Tu sesión venció. Volvé a iniciar sesión.';
    return generico;
  }
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (esCredencialIncorrecta(error)) return 'Usuario o contraseña incorrectos. Revisá bien los datos.';
    if (error.code == 'user_banned' || m.contains('banned')) return 'Tu usuario está desactivado. Hablá con el administrador.';
    if (m.contains('rate limit') || error.statusCode == '429') return 'Demasiados intentos seguidos. Esperá un minuto y volvé a intentar.';
    if (error is AuthRetryableFetchException) return 'No hay conexión a internet. Revisá el wifi o los datos móviles.';
    return 'No se pudo iniciar sesión. Revisá tu conexión e intentá de nuevo.';
  }
  if (esSinConexion(error)) return 'No hay conexión a internet. Revisá el wifi o los datos móviles.';
  if (error is FileSystemException) return 'No se pudieron guardar los datos en el equipo. Revisá que haya espacio libre.';
  return generico;
}
