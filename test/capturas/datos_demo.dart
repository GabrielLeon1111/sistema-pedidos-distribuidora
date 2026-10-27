// Datos de ejemplo para las capturas del README. Todo es inventado.

/// Un local, productos, notas de pedido, ventas y hojas de proveedor ficticios.
class Demo {
  static final _hoy = DateTime.now();
  static String _fecha(int diasAtras, [int hora = 10]) =>
      DateTime(_hoy.year, _hoy.month, _hoy.day, hora).subtract(Duration(days: diasAtras)).toIso8601String();

  static final negocio = <String, dynamic>{
    'id': 'negocio',
    'nombre': 'Distribuidora AM',
    'rubro': 'Distribuidora',
    'propietario': 'Juan Carlos Benítez',
    'actividades': 'Comercio al por menor de cosméticos y artículos de tocador - Bazar - Ferretería',
    'direccion': 'Calle Principal 123 - Barrio Centro',
    'ciudad': 'Asunción',
    'telefono': '0981 - 000 000',
    'ruc': '4501238-7',
  };

  static final proveedores = <Map<String, dynamic>>[
    {'id': 'prov1', 'nombre': 'Proveedor de Ejemplo S.A.', 'telefono': '0981 222 333', 'activo': true, 'creado': _fecha(90)},
  ];

  static Map<String, dynamic> _cliente(String id, String nombre, String contacto) => {
        'id': id,
        'nombre': nombre,
        'contacto': contacto,
        'telefono': '0981 000 000',
        'direccion': 'Barrio Centro',
        'activo': true,
        'creado': _fecha(60),
      };

  static final clientes = <Map<String, dynamic>>[
    _cliente('c1', 'Despensa La Familia', 'Rosa'),
    _cliente('c2', 'Almacén San Roque', 'Pedro'),
    _cliente('c3', 'Minimercado El Sol', 'Lucía'),
    _cliente('c4', 'Despensa Doña Marta', 'Marta'),
    _cliente('c5', 'Farmacia Central', 'Carlos'),
  ];

  static Map<String, dynamic> _producto(String id, String nombre, String categoria, int venta, int compra,
          {String unidad = 'unidad', double stock = 0, int iva = 10, List<Map<String, dynamic>> formas = const []}) =>
      {
        'id': id,
        'nombre': nombre,
        'unidad': unidad,
        'categoria': categoria,
        'precio_venta': venta,
        'precio_compra': compra,
        'stock': stock,
        'costo_promedio': compra,
        'stock_minimo': 5,
        'iva': iva,
        'activo': true,
        'creado': _fecha(80),
        'presentaciones': formas,
      };

  static final productos = <Map<String, dynamic>>[
    _producto('zap', 'Zapatilla havaiana clásica 34/39', 'Calzados', 36000, 29000, stock: 30, formas: [
      {'nombre': 'docena', 'unidades': 12, 'precio': 430000},
    ]),
    _producto('tin', 'Tinte para cabello NANTYR', 'Belleza y accesorios', 12000, 8500, stock: 14),
    _producto('kit', 'Kitadol Forte x20', 'Medicamentos', 9500, 7000, unidad: 'caja', stock: 40, iva: 5),
    _producto('nov', 'Novalgina gota 10 ml', 'Medicamentos', 24500, 18500, unidad: 'frasco', stock: 8, iva: 5),
    _producto('jar', 'Jarra plástica nacional', 'Vajilla, vasos y jarras', 8500, 6000, stock: 3),
    _producto('vas', 'Vaso de vidrio x6', 'Vajilla, vasos y jarras', 20000, 15000, unidad: 'caja', stock: 12),
    _producto('deo', 'Desodorante Rexona aerosol', 'Higiene personal', 18000, 13500, stock: 24),
    _producto('pil', 'Pila AA Royal x60', 'Electricidad, iluminación y pilas', 30000, 22000, unidad: 'paquete', stock: 6),
    _producto('foc', 'Foco led MB 12W', 'Electricidad, iluminación y pilas', 10000, 7000, stock: 50),
    _producto('esc', 'Escoba', 'Hogar, limpieza y descartables', 11500, 8000, stock: 0),
  ];

  static Map<String, dynamic> _linea(String id, String prod, double cant, {String? unidad, double factor = 1, String? nota, String estado = 'pendiente'}) {
    final p = productos.firstWhere((x) => x['id'] == prod);
    final forma = unidad == null ? null : (p['presentaciones'] as List).firstWhere((f) => f['nombre'] == unidad);
    final precio = forma == null ? p['precio_venta'] as int : forma['precio'] as int;
    return {
      'id': id,
      'producto_id': prod,
      'descripcion': p['nombre'],
      'unidad': unidad ?? p['unidad'],
      'factor': factor,
      'nota': nota,
      'cantidad': cant,
      'precio': precio,
      'costo': 0,
      'iva': p['iva'],
      'estado': estado,
    };
  }

  static Map<String, dynamic> _pedido(String id, int numero, String clienteId, int dias, List<Map<String, dynamic>> lineas,
      {String estado = 'cargado', String? obs}) {
    final c = clientes.firstWhere((x) => x['id'] == clienteId);
    return {
      'id': id,
      'numero': numero,
      'fecha': _fecha(dias, 9 + numero % 8),
      'cliente_id': clienteId,
      'cliente': {'nombre': c['nombre'], 'contacto': c['contacto'], 'telefono': c['telefono'], 'direccion': c['direccion']},
      'vendedor_nombre': 'Pedro Vendedor',
      'lineas': lineas,
      'estado': estado,
      'observaciones': obs,
    };
  }

  static final pedidos = <Map<String, dynamic>>[
    _pedido('p1', 128, 'c1', 0, [
      _linea('a1', 'tin', 3, nota: '1 rubio, 2 negros'),
      _linea('a2', 'zap', 2, unidad: 'docena', factor: 12, nota: '6 del 35, 6 del 36, 12 del 38'),
      _linea('a3', 'kit', 5),
      _linea('a4', 'deo', 6, nota: '3 hombre, 3 mujer'),
    ], obs: 'Entregar el jueves a la mañana.'),
    _pedido('p2', 127, 'c2', 0, [_linea('b1', 'jar', 6), _linea('b2', 'vas', 2), _linea('b3', 'foc', 10)]),
    _pedido('p3', 126, 'c3', 1, [_linea('c1', 'nov', 4), _linea('c2', 'kit', 10), _linea('c3', 'pil', 1)]),
    _pedido('p4', 125, 'c4', 1, [_linea('d1', 'esc', 3), _linea('d2', 'deo', 12, nota: 'Todos de mujer')], estado: 'pedido'),
    _pedido('p5', 124, 'c5', 2, [_linea('e1', 'kit', 20), _linea('e2', 'nov', 6)], estado: 'recibido'),
  ];

  static Map<String, dynamic> _venta(String id, int numero, String clienteId, int dias, int total, int costo, int pagado) {
    final c = clientes.firstWhere((x) => x['id'] == clienteId);
    return {
      'id': id,
      'numero': numero,
      'fecha': _fecha(dias, 15),
      'cliente_id': clienteId,
      'cliente': {'nombre': c['nombre']},
      'lineas': <Map<String, dynamic>>[],
      'total': total,
      'costo_total': costo,
      'pagado': pagado,
      'anulada': false,
    };
  }

  static final ventas = <Map<String, dynamic>>[
    _venta('v1', 64, 'c1', 0, 486000, 372000, 486000),
    _venta('v2', 63, 'c3', 0, 215500, 160000, 100000),
    _venta('v3', 62, 'c2', 2, 352000, 268000, 352000),
    _venta('v4', 61, 'c4', 5, 128000, 96000, 0),
    _venta('v5', 60, 'c5', 9, 640000, 488000, 640000),
    for (var m = 1; m < 7; m++) _venta('h$m', 50 - m, 'c${1 + m % 5}', 30 * m + 3, 2600000 + 380000 * (m % 3), 1950000, 2600000),
  ];

  static final pagos = <Map<String, dynamic>>[
    {'id': 'g1', 'numero': 40, 'fecha': _fecha(0, 16), 'cliente_id': 'c1', 'cliente_nombre': 'Despensa La Familia', 'monto': 486000, 'metodo': 'efectivo', 'anulado': false},
    {'id': 'g2', 'numero': 39, 'fecha': _fecha(0, 17), 'cliente_id': 'c3', 'cliente_nombre': 'Minimercado El Sol', 'monto': 100000, 'metodo': 'transferencia', 'anulado': false},
  ];

  static Map<String, dynamic> _lineaHoja(String prod, double cant, List<(String, int, String, double, String?)> det, {String? unidad, double factor = 1}) {
    final p = productos.firstWhere((x) => x['id'] == prod);
    final notas = [for (final d in det) ?d.$5];
    return {
      'producto_id': prod,
      'descripcion': p['nombre'],
      'unidad': unidad ?? p['unidad'],
      'factor': factor,
      'cantidad': cant,
      'nota': notas.isEmpty ? null : notas.join(' · '),
      'detalle': [
        for (final d in det) {'pedido_id': d.$1, 'pedido_numero': d.$2, 'linea_id': '${d.$1}-$prod', 'cliente_nombre': d.$3, 'cantidad': d.$4, 'nota': d.$5},
      ],
      'recepcion': 'pendiente',
      'cantidad_recibida': 0,
      'precio_compra': ((p['precio_compra'] as int) * factor).round(),
    };
  }

  static final consolidados = <Map<String, dynamic>>[
    {
      'id': 'h1',
      'numero': 18,
      'fecha': _fecha(1, 18),
      'proveedor_id': 'prov1',
      'proveedor_nombre': 'Proveedor de Ejemplo S.A.',
      'proveedor_telefono': '0981 222 333',
      'pedido_ids': ['p4'],
      'creado_por': 'Juan Benítez',
      'estado': 'enviado',
      'directa': false,
      'lineas': [
        _lineaHoja('deo', 12, [('p4', 125, 'Despensa Doña Marta', 12, 'Todos de mujer')]),
        _lineaHoja('esc', 3, [('p4', 125, 'Despensa Doña Marta', 3, null)]),
      ],
    },
    {
      'id': 'h2',
      'numero': 19,
      'fecha': _fecha(0, 8),
      'proveedor_id': 'compra',
      'proveedor_nombre': 'Compra directa',
      'pedido_ids': ['p1', 'p2', 'p3'],
      'creado_por': 'Juan Benítez',
      'estado': 'enviado',
      'directa': true,
      'lineas': [
        _lineaHoja('tin', 3, [('p1', 128, 'Despensa La Familia', 3, '1 rubio, 2 negros')]),
        _lineaHoja('zap', 2, [('p1', 128, 'Despensa La Familia', 2, '6 del 35, 6 del 36, 12 del 38')], unidad: 'docena', factor: 12),
        _lineaHoja('kit', 15, [('p1', 128, 'Despensa La Familia', 5, null), ('p3', 126, 'Minimercado El Sol', 10, null)]),
        _lineaHoja('nov', 4, [('p3', 126, 'Minimercado El Sol', 4, null)]),
        _lineaHoja('jar', 6, [('p2', 127, 'Almacén San Roque', 6, null)]),
        _lineaHoja('vas', 2, [('p2', 127, 'Almacén San Roque', 2, null)]),
      ],
    },
  ];
}
