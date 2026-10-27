import 'json.dart';

/// Una línea del registro de cambios: quién hizo qué y cuándo.
class Cambio {
  final String id;
  final DateTime fecha;
  final String usuarioNombre;
  final String area;
  final String accion;
  final String detalle;
  final bool importante;

  const Cambio({
    required this.id,
    required this.fecha,
    required this.usuarioNombre,
    required this.area,
    required this.accion,
    required this.detalle,
    this.importante = false,
  });

  factory Cambio.fromMap(Map<String, dynamic> m) => Cambio(
        id: m['id'] as String,
        fecha: toDate(m['fecha']),
        usuarioNombre: (m['usuario_nombre'] as String?) ?? 'Sistema',
        area: m['area'] as String,
        accion: m['accion'] as String,
        detalle: (m['detalle'] as String?) ?? '',
        importante: toBool(m['importante']),
      );
}

/// Áreas del historial (para filtrar).
abstract final class Area {
  static const pedidos = 'Pedidos';
  static const proveedor = 'Proveedor';
  static const entregas = 'Entregas';
  static const cobros = 'Cobros';
  static const inventario = 'Inventario';
  static const clientes = 'Clientes';
  static const gastos = 'Gastos';
  static const usuarios = 'Usuarios';
  static const negocio = 'Negocio';
  static const todas = [pedidos, proveedor, entregas, cobros, inventario, clientes, gastos, usuarios, negocio];
}
