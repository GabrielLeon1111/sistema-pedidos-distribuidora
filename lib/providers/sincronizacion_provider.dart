import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/local.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/pedido_repository.dart';
import '../repositories/producto_repository.dart';
import '../security/registro_seguro.dart';
import 'refresh_bus.dart';

/// Sube solo lo que se levantó sin señal (locales y notas de pedido), reserva
/// números de pedido y actualiza la copia de locales y productos del teléfono.
/// Corre al entrar, cada 30 segundos y cada vez que se guarda algo.
class SincronizacionProvider extends ChangeNotifier {
  SincronizacionProvider({required this.pedidos, required this.clientes, required this.productos, required this.local, required this.bus});

  final PedidoRepository pedidos;
  final ClienteRepository clientes;
  final ProductoRepository productos;
  final Local local;
  final RefreshBus bus;

  static const _cada = Duration(seconds: 30);

  Timer? _timer;
  bool _sincronizando = false;
  bool _enLinea = true;
  int _pendientes = 0;
  int _conError = 0;

  bool get sincronizando => _sincronizando;

  /// La última vez que se intentó, hubo respuesta del servidor.
  bool get enLinea => _enLinea;

  /// Notas de pedido y locales que todavía no se subieron.
  int get pendientes => _pendientes;

  /// De esos, cuántos rechazó el servidor (hay que corregirlos).
  int get conError => _conError;

  void iniciar() {
    _timer?.cancel();
    _timer = Timer.periodic(_cada, (_) => sincronizar());
    sincronizar();
  }

  void detener() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> sincronizar() async {
    if (_sincronizando) return;
    _sincronizando = true;
    notifyListeners();
    var subidos = 0;
    try {
      // Primero los locales: las notas nuevas pueden ser de un local nuevo.
      subidos += await clientes.subirPendientes();
      subidos += await pedidos.subirPendientes();
      await pedidos.asegurarNumeros();
      await productos.listar();
      await clientes.listar();
      _enLinea = true;
    } catch (e) {
      if (esSinConexion(e)) {
        _enLinea = false;
      } else {
        registrarError('sincronizar', e);
      }
    } finally {
      await _contar();
      _sincronizando = false;
      notifyListeners();
      if (subidos > 0) bus.changed();
    }
  }

  /// Vuelve a contar lo pendiente (después de guardar algo sin señal).
  Future<void> recontar() async {
    await _contar();
    notifyListeners();
  }

  Future<void> _contar() async {
    final cola = [...await local.cola('pedidos'), ...await local.cola('clientes')];
    _pendientes = cola.length;
    _conError = cola.where((f) => f['error_sincronizacion'] != null).length;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
