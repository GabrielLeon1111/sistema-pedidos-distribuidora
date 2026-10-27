import 'package:intl/intl.dart';
import '../utils/formato.dart';
import 'json.dart';

/// Qué pasó con la línea cuando llegó la mercadería del proveedor.
enum EstadoLinea {
  pendiente('pendiente', 'Esperando mercadería'),
  llego('llego', 'Llegó'),
  parcial('parcial', 'Llegó una parte'),
  noLlego('no_llego', 'No llegó'),
  rechazada('rechazada', 'El local no aceptó');

  const EstadoLinea(this.valor, this.texto);
  final String valor;
  final String texto;

  static EstadoLinea de(String? v) => values.firstWhere((e) => e.valor == v, orElse: () => pendiente);
}

/// Una línea de nota de pedido o de nota de venta.
class Linea {
  final String id;
  final String? productoId;
  final String? codigo;
  final String descripcion;
  /// La forma en que se vende (unidad, docena, paquete...).
  final String unidad;

  /// Cuántas unidades del stock es cada una (12 si es la docena).
  final double factor;

  /// Detalle libre del pedido (ej. tinte: "1 rubio, 2 negros"). Sale en la
  /// nota de pedido y en la hoja del proveedor.
  final String? nota;

  /// Lo que pidió el local.
  final double cantidad;

  /// Precio de venta por [unidad] (por docena si se vende la docena).
  final int precio;

  /// Descuento en porcentaje (se recalcula si cambia la cantidad) o monto fijo.
  final double? descPct;
  final int descMonto;

  /// Se entrega de la mercadería en stock (no se le pide al proveedor).
  final bool deStock;

  /// Costo por unidad (lo que se pagó al proveedor). Solo lo ve el administrador.
  final int costo;

  /// Tasa de IVA (10, 5 o 0 = exenta). El precio ya incluye el IVA.
  final int iva;

  final EstadoLinea estado;

  /// Lo que finalmente se entrega si llegó una parte (null = lo pedido).
  final double? cantidadFinal;

  /// 'esperando' mientras el local no confirma que acepta la cantidad parcial.
  final String? confirmacion;

  const Linea({
    required this.id,
    this.productoId,
    this.codigo,
    required this.descripcion,
    this.unidad = 'unidad',
    this.factor = 1,
    this.nota,
    required this.cantidad,
    required this.precio,
    this.descPct,
    this.descMonto = 0,
    this.deStock = false,
    this.costo = 0,
    this.iva = 10,
    this.estado = EstadoLinea.pendiente,
    this.cantidadFinal,
    this.confirmacion,
  });

  bool get anulada => estado == EstadoLinea.noLlego || estado == EstadoLinea.rechazada;
  bool get esperandoConfirmacion => confirmacion == 'esperando';

  /// Lo que se entrega y se cobra.
  double get cantidadEfectiva => anulada ? 0 : (cantidadFinal ?? cantidad);
  bool get cambioCantidad => cantidadEfectiva != cantidad;

  /// Cuántas unidades del stock son (3 docenas = 36).
  double get cantidadEnStock => cantidadEfectiva * factor;

  /// "docenas", o "paquetes de 12" si no se sabe por el nombre cuántas trae.
  String unidadTexto([num? cant]) => textoForma(unidad, factor, cant ?? cantidad);

  int _bruto(double q) => (q * precio).round();

  int _descuento(double q) {
    final bruto = _bruto(q);
    if (bruto <= 0) return 0;
    final d = descPct != null
        ? (bruto * descPct! / 100).round()
        : (cantidad <= 0 ? 0 : (descMonto * q / cantidad).round());
    return d.clamp(0, bruto);
  }

  /// Total sin descuento (con la cantidad que se entrega).
  int get bruto => _bruto(cantidadEfectiva);
  int get descuento => _descuento(cantidadEfectiva);
  int get total => bruto - descuento;

  /// Total de lo que se pidió originalmente.
  int get totalPedido => _bruto(cantidad) - _descuento(cantidad);

  int get costoTotal => (cantidadEfectiva * costo).round();
  int get ganancia => total - costoTotal;

  /// Precio unitario ya con descuento (para el margen).
  int get precioNeto => cantidadEfectiva <= 0 ? precio : (total / cantidadEfectiva).round();

  bool get tieneDescuento => (descPct != null && descPct! > 0) || descMonto > 0;

  /// "Desc. 10% (−Gs. 15.000)" o "Desc. −Gs. 5.000"
  String? get textoDescuento {
    if (!tieneDescuento || descuento == 0) return null;
    if (descPct != null) return 'Desc. ${NumberFormat('#,##0.##', 'es').format(descPct)}% (−${gs(descuento)})';
    return 'Desc. −${gs(descuento)}';
  }

  factory Linea.fromMap(Map<String, dynamic> m) => Linea(
        id: m['id'] as String,
        productoId: m['producto_id'] as String?,
        codigo: textOrNull(m['codigo']),
        descripcion: m['descripcion'] as String,
        unidad: (m['unidad'] as String?) ?? 'unidad',
        factor: m['factor'] == null ? 1 : toDouble(m['factor']),
        nota: textOrNull(m['nota']),
        cantidad: toDouble(m['cantidad']),
        precio: toInt(m['precio']),
        descPct: m['desc_pct'] == null ? null : toDouble(m['desc_pct']),
        descMonto: toInt(m['desc_monto']),
        deStock: toBool(m['de_stock']),
        costo: toInt(m['costo']),
        iva: m['iva'] == null ? 10 : toInt(m['iva']),
        estado: EstadoLinea.de(m['estado'] as String?),
        cantidadFinal: m['cantidad_final'] == null ? null : toDouble(m['cantidad_final']),
        confirmacion: m['confirmacion'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'producto_id': productoId,
        'codigo': codigo,
        'descripcion': descripcion,
        'unidad': unidad,
        'factor': factor,
        'nota': nota,
        'cantidad': cantidad,
        'precio': precio,
        'desc_pct': descPct,
        'desc_monto': descMonto,
        'de_stock': deStock,
        'costo': costo,
        'iva': iva,
        'estado': estado.valor,
        'cantidad_final': cantidadFinal,
        'confirmacion': confirmacion,
      };

  /// Sin el costo (lo que se guarda en el celular del vendedor o se le muestra).
  Linea sinCosto() => copyWith(costo: 0);

  Linea copyWith({
    double? cantidad,
    int? precio,
    double? descPct,
    bool quitarDescPct = false,
    int? descMonto,
    bool? deStock,
    int? costo,
    int? iva,
    EstadoLinea? estado,
    double? cantidadFinal,
    bool quitarCantidadFinal = false,
    String? confirmacion,
    bool quitarConfirmacion = false,
    String? descripcion,
    String? codigo,
    String? unidad,
    double? factor,
    String? nota,
    String? productoId,
  }) =>
      Linea(
        id: id,
        productoId: productoId ?? this.productoId,
        codigo: codigo ?? this.codigo,
        descripcion: descripcion ?? this.descripcion,
        unidad: unidad ?? this.unidad,
        factor: factor ?? this.factor,
        nota: nota ?? this.nota,
        cantidad: cantidad ?? this.cantidad,
        precio: precio ?? this.precio,
        descPct: quitarDescPct ? null : (descPct ?? this.descPct),
        descMonto: descMonto ?? this.descMonto,
        deStock: deStock ?? this.deStock,
        costo: costo ?? this.costo,
        iva: iva ?? this.iva,
        estado: estado ?? this.estado,
        cantidadFinal: quitarCantidadFinal ? null : (cantidadFinal ?? this.cantidadFinal),
        confirmacion: quitarConfirmacion ? null : (confirmacion ?? this.confirmacion),
      );
}

int sumaTotales(Iterable<Linea> lineas) => lineas.fold(0, (s, l) => s + l.total);
