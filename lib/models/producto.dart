import '../utils/formato.dart';
import 'json.dart';

/// Producto. No hace falta cargar el catálogo: la app lo recuerda la primera
/// vez que se pide, con su último precio de venta y de compra.
class Producto {
  final String id;
  final String? codigo;
  final String nombre;
  final String unidad;
  final String? categoria;
  final String? marca;
  final String? proveedorId;

  /// Último precio al que se vendió (se sugiere en el próximo pedido).
  final int precioVenta;

  /// Último precio que se le pagó al proveedor (se sugiere en la recepción).
  final int precioCompra;

  final double stock;

  /// Costo promedio de lo que hay en stock.
  final int costoPromedio;
  final double stockMinimo;

  /// Tasa de IVA para la factura: 10, 5 o 0 (exenta).
  final int iva;
  final bool activo;
  final DateTime creado;

  /// Otras formas de venta además de la unidad (docena, paquete, caja...).
  /// El stock siempre se cuenta en [unidad].
  final List<Presentacion> presentaciones;

  const Producto({
    required this.id,
    this.codigo,
    required this.nombre,
    this.unidad = 'unidad',
    this.categoria,
    this.marca,
    this.proveedorId,
    this.precioVenta = 0,
    this.precioCompra = 0,
    this.stock = 0,
    this.costoPromedio = 0,
    this.stockMinimo = 0,
    this.iva = 10,
    this.activo = true,
    required this.creado,
    this.presentaciones = const [],
  });

  factory Producto.fromMap(Map<String, dynamic> m) => Producto(
        id: m['id'] as String,
        codigo: textOrNull(m['codigo']),
        nombre: m['nombre'] as String,
        unidad: (m['unidad'] as String?) ?? 'unidad',
        categoria: textOrNull(m['categoria']),
        marca: textOrNull(m['marca']),
        proveedorId: m['proveedor_id'] as String?,
        precioVenta: toInt(m['precio_venta']),
        precioCompra: toInt(m['precio_compra']),
        stock: toDouble(m['stock']),
        costoPromedio: toInt(m['costo_promedio']),
        stockMinimo: toDouble(m['stock_minimo']),
        iva: m['iva'] == null ? 10 : toInt(m['iva']),
        activo: m['activo'] != false,
        creado: toDate(m['creado']),
        presentaciones: [
          if (m['presentaciones'] is List)
            for (final x in m['presentaciones'] as List) Presentacion.fromMap(Map<String, dynamic>.from(x as Map)),
        ],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'codigo': textOrNull(codigo),
        'nombre': nombre.trim(),
        'unidad': unidad,
        'categoria': textOrNull(categoria),
        'marca': textOrNull(marca),
        'proveedor_id': proveedorId,
        'precio_venta': precioVenta,
        'precio_compra': precioCompra,
        'stock': stock,
        'costo_promedio': costoPromedio,
        'stock_minimo': stockMinimo,
        'iva': iva,
        'activo': activo,
        'creado': creado.toIso8601String(),
        'presentaciones': [for (final x in presentaciones) x.toMap()],
      };

  /// Todas las formas en que se vende: primero la unidad, después las demás.
  List<Presentacion> get formasDeVenta => [Presentacion(nombre: unidad, unidades: 1, precio: precioVenta), ...presentaciones];

  /// La forma de venta con ese nombre (la unidad si no existe).
  Presentacion forma(String? nombre) =>
      formasDeVenta.firstWhere((f) => f.nombre.toLowerCase() == (nombre ?? unidad).toLowerCase(), orElse: () => formasDeVenta.first);

  /// "Gs. 36.000 la unidad · Gs. 430.500 la docena"
  String get textoPrecios => formasDeVenta.where((f) => f.precio > 0).map((f) => '${gs(f.precio)} ${f.nombre}').join(' · ');

  /// El costo que se usa para la ganancia: el promedio del stock o, si no hay,
  /// el último precio de compra.
  int get costoReferencia => costoPromedio > 0 ? costoPromedio : precioCompra;

  /// Valor de la mercadería en stock (a costo).
  int get valorStock => stock <= 0 ? 0 : (stock * costoReferencia).round();

  EstadoStock get estadoStock {
    if (stock <= 0) return EstadoStock.agotado;
    if (stock <= stockMinimo) return EstadoStock.porAgotarse;
    return EstadoStock.disponible;
  }

  double? get margenPorcentaje => margenPct(precioVenta, precioCompra);
  int get gananciaUnidad => precioVenta - precioCompra;

  /// "COD-12 · Arroz Tío Pancho 1kg"
  String get etiqueta => codigo == null ? nombre : '$codigo · $nombre';

  bool coincide(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return true;
    return nombre.toLowerCase().contains(t) ||
        (codigo?.toLowerCase().startsWith(t) ?? false) ||
        (marca?.toLowerCase().contains(t) ?? false);
  }
}

/// Una forma de venta: cuántas [unidades] del producto trae y su precio.
class Presentacion {
  final String nombre;
  final double unidades;
  final int precio;

  const Presentacion({required this.nombre, required this.unidades, this.precio = 0});

  factory Presentacion.fromMap(Map<String, dynamic> m) =>
      Presentacion(nombre: (m['nombre'] as String?) ?? 'unidad', unidades: toDouble(m['unidades']), precio: toInt(m['precio']));

  Map<String, dynamic> toMap() => {'nombre': nombre, 'unidades': unidades, 'precio': precio};

  bool get esUnidad => unidades == 1;
}

enum EstadoStock {
  disponible('Disponible'),
  porAgotarse('Por agotarse'),
  agotado('Agotado');

  const EstadoStock(this.texto);
  final String texto;
}

/// Tasas de IVA de Paraguay (0 = exenta).
const tasasIva = [10, 5, 0];

String ivaTexto(int iva) => iva == 0 ? 'Exenta' : 'IVA $iva %';

/// Unidades sugeridas al crear un producto.
const unidadesSugeridas = ['unidad', 'caja', 'paquete', 'docena', 'tira', 'par', 'juego', 'rollo', 'frasco', 'pack', 'kg', 'lt', 'bolsa', 'fardo', 'm'];

/// Nombres sugeridos para las otras formas de venta.
const formasSugeridas = ['docena', 'paquete', 'caja', 'tira', 'pack', 'bolsa', 'fardo'];
