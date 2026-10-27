// =================================================================
//  CONTRASEÑAS (mientras los datos están en el equipo)
//  Nunca se guarda la contraseña: solo un resumen (hash) con sal, repetido
//  muchas veces para que sea lento de adivinar. Al pasar a Supabase, las
//  contraseñas las maneja Supabase Auth y este archivo deja de usarse.
// =================================================================
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

const _vueltas = 20000;

String nuevaSal() {
  final r = Random.secure();
  return base64UrlEncode(List<int>.generate(16, (_) => r.nextInt(256)));
}

String hashClave(String clave, String sal) {
  List<int> d = utf8.encode('$sal:$clave');
  for (var i = 0; i < _vueltas; i++) {
    d = sha256.convert(d).bytes;
  }
  return base64Encode(d);
}

/// Compara sin cortar en el primer carácter distinto (no da pistas por el tiempo).
bool claveCorrecta(String clave, String sal, String hash) {
  final a = hashClave(clave, sal);
  if (a.length != hash.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ hash.codeUnitAt(i);
  }
  return diff == 0;
}

/// Reglas de la contraseña (las mismas que se pedirán en Supabase).
String? validarClave(String? v) {
  final t = v ?? '';
  if (t.isEmpty) return 'Escribí la contraseña';
  if (t.length < 6) return 'Mínimo 6 caracteres';
  if (t.length > 72) return 'Máximo 72 caracteres';
  return null;
}
