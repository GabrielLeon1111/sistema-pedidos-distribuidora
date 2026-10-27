import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/negocio.dart';
import '../repositories/negocio_repository.dart';
import '../security/registro_seguro.dart';

/// Datos del negocio (salen en todos los documentos).
///
/// Se guarda una copia en el equipo: así la pantalla de ingreso muestra el
/// encabezado del negocio (sin sesión la base no deja leerlo) y se ve igual
/// aunque no haya señal.
class NegocioProvider extends ChangeNotifier {
  NegocioProvider(this._repo);
  final NegocioRepository _repo;
  static const _kCopia = 'negocio_encabezado';

  Negocio _negocio = const Negocio();
  Negocio get negocio => _negocio;

  /// Ya se sabe el nombre de verdad (de la copia del equipo o de la base).
  /// Mientras tanto no se muestra nada, para que no aparezca "Mi Negocio"
  /// por un instante.
  bool _listo = false;
  bool get listo => _listo;

  /// Si la app ya tiene administrador (null: todavía no se sabe, por ejemplo sin señal).
  /// Mientras no haya ninguno, el ingreso ofrece crearlo.
  bool? _tieneAdmin;
  bool? get tieneAdmin => _tieneAdmin;

  /// Ya se leyeron todos los datos con la sesión abierta (no se pisan con el encabezado).
  bool _completo = false;
  Timer? _reintento;
  bool _cerrado = false;

  /// Al abrir la app: primero la copia del equipo (sirve sin señal) y después
  /// el encabezado que entrega la base sin sesión.
  Future<void> restaurar() async {
    try {
      final txt = (await SharedPreferences.getInstance()).getString(_kCopia);
      if (_cerrado) return;
      if (txt != null && !_completo) {
        _negocio = Negocio.fromMap(Map<String, dynamic>.from(jsonDecode(txt) as Map));
        _listo = true;
        notifyListeners();
      }
    } catch (e) {
      registrarError('restaurarNegocio', e);
    }
    await _leerEncabezado();
  }

  Future<void> _leerEncabezado() async {
    if (_cerrado) return;
    _reintento?.cancel();
    try {
      final e = await _repo.encabezado();
      if (_cerrado) return;
      if (e != null) {
        _tieneAdmin = e['tiene_admin'] == true;
        if (!_completo) {
          _negocio = Negocio.fromMap({..._negocio.toMap(), ...e});
          _guardarCopia(_negocio);
        }
        _listo = true;
        notifyListeners();
        return;
      }
    } catch (e) {
      registrarError('encabezadoNegocio', e);
    }
    // Sin datos reales, el nombre queda oculto y se vuelve a intentar.
    // El temporizador se cancela al obtener datos o al cerrar el provider.
    if (!_cerrado && !_listo && !_completo) {
      _reintento = Timer(const Duration(seconds: 2), _leerEncabezado);
    }
  }

  Future<void> cargar() async {
    try {
      final n = await _repo.obtener();
      _completo = true;
      _poner(n);
    } catch (e) {
      registrarError('cargarNegocio', e);
    }
  }

  Future<void> guardar(Negocio n) async {
    await _repo.guardar(n);
    _poner(n);
  }

  void _poner(Negocio n) {
    if (_cerrado) return;
    _reintento?.cancel();
    _negocio = n;
    _listo = true;
    notifyListeners();
    _guardarCopia(n);
  }

  void _guardarCopia(Negocio n) {
    SharedPreferences.getInstance().then((p) => p.setString(_kCopia, jsonEncode(n.toMap()))).catchError((Object e) {
      registrarError('copiaNegocio', e);
      return false;
    });
  }

  @override
  void dispose() {
    _cerrado = true;
    _reintento?.cancel();
    super.dispose();
  }
}
