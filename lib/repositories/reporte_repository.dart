import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/compra.dart';
import '../models/consolidado.dart';
import '../models/ganancia.dart';
import '../models/gasto.dart';
import '../models/movimiento.dart';
import '../models/pago.dart';
import '../models/pedido.dart';
import '../models/producto.dart';
import '../models/reportes.dart';
import '../models/venta.dart';
import '../utils/formato.dart';

/// Inicio y reportes: se leen las tablas (solo el administrador) y se calcula acá.
class ReporteRepository {
  ReporteRepository(this._s, this._sesion);
  final Servidor _s;
  final Sesion _sesion;

  Future<List<Venta>> _ventas() async =>
      [for (final f in await _s.filas('ventas', filtro: (q) => q.eq('anulada', false))) Venta.fromMap(f)];

  Periodo _periodo(List<Venta> ventas, DateTime desde, DateTime hasta) {
    final vs = ventas.where((v) => !v.fecha.isBefore(desde) && !v.fecha.isAfter(hasta));
    return Periodo(
      vendido: vs.fold(0, (s, v) => s + v.total),
      ganancia: vs.fold(0, (s, v) => s + v.ganancia),
      notas: vs.length,
    );
  }

  List<ProductoRanking> _porProducto(Iterable<Venta> ventas) {
    final m = <String, ProductoRanking>{};
    for (final v in ventas) {
      for (final l in v.lineas) {
        // Cada forma de venta por separado (docenas y unidades no se suman).
        final k = '${l.productoId ?? l.descripcion}|${l.unidad}';
        final p = m[k];
        m[k] = ProductoRanking(
          nombre: l.unidad == 'unidad' ? l.descripcion : '${l.descripcion} (${l.unidad})',
          unidad: l.unidad,
          cantidad: (p?.cantidad ?? 0) + l.cantidad,
          vendido: (p?.vendido ?? 0) + l.total,
          ganancia: (p?.ganancia ?? 0) + l.ganancia,
        );
      }
    }
    return m.values.toList()..sort((a, b) => b.vendido.compareTo(a.vendido));
  }

  Future<Panel> panel() async {
    _sesion.exigirAdmin();
    final (ventas, pedidosF, pagosF, productosF, sinRecibir) = await (
      _ventas(),
      _s.rpcLista('listar_pedidos'),
      _s.filas('pagos', filtro: (q) => q.eq('anulado', false)),
      _s.filas('productos'),
      _s.filas('consolidados', filtro: (q) => q.eq('estado', 'enviado')),
    ).wait;
    final ahora = DateTime.now();
    final hoy = inicioDia(ahora);
    final fin = finDia(ahora);
    final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
    final inicioMes = DateTime(hoy.year, hoy.month);
    final inicioMesAnt = DateTime(hoy.year, hoy.month - 1);
    // Mismo tramo del mes anterior (si hoy es 31 y el mes anterior tiene 30, hasta el 30).
    final ultimoDiaAnt = DateTime(hoy.year, hoy.month, 0).day;
    final finMesAnt = finDia(DateTime(hoy.year, hoy.month - 1, hoy.day > ultimoDiaAnt ? ultimoDiaAnt : hoy.day));
    final delMes = ventas.where((v) => !v.fecha.isBefore(inicioMes));
    final ranking = _porProducto(delMes);

    final pedidos = [for (final f in pedidosF) Pedido.fromMap(f)];
    final pagos = [for (final f in pagosF) Pago.fromMap(f)];
    final todos = [for (final f in productosF) Producto.fromMap(f)];
    final productos = todos.where((p) => p.activo).toList();
    final abiertas = pedidos.where((p) => !p.cerrado).toList();
    final deudas = <String, int>{};
    for (final v in ventas) {
      if (v.saldo > 0) deudas[v.clienteId] = (deudas[v.clienteId] ?? 0) + v.saldo;
    }
    final porEntregar = pedidos.where((p) => p.entregable || (p.estado == EstadoPedido.recibido && p.esperandoConfirmacion));

    return Panel(
      hoy: _periodo(ventas, hoy, fin),
      semana: _periodo(ventas, lunes, fin),
      mes: _periodo(ventas, inicioMes, fin),
      anio: _periodo(ventas, DateTime(hoy.year), fin),
      mesAnterior: _periodo(ventas, inicioMesAnt, finMesAnt),
      cobradoHoy: pagos.where((p) => !p.fecha.isBefore(hoy)).fold(0, (s, p) => s + p.monto),
      totalDeuda: deudas.values.fold(0, (s, d) => s + d),
      localesQueDeben: deudas.length,
      masVendidos: ranking.take(5).toList(),
      masGanancia: ([...ranking]..sort((a, b) => b.ganancia.compareTo(a.ganancia))).take(5).toList(),
      avisos: Avisos(
        esperandoConfirmacion: pedidos.where((p) => p.esperandoConfirmacion && !p.cerrado).length,
        sinEntregar: porEntregar.length,
        entregasAtrasadas: porEntregar.where((p) => p.fechaEntrega != null && p.fechaEntrega!.isBefore(hoy)).length,
        sinRecibir: sinRecibir.length,
        sinPedir: pedidos.where((p) => p.estado == EstadoPedido.cargado && p.lineasAProveedor.isNotEmpty).length,
        stockBajo: productos.where((p) => p.stockMinimo > 0 && p.stock <= p.stockMinimo).length,
      ),
      pendiente: EstimacionGanancia.de(abiertas.expand((p) => p.lineas), todos),
      notasPendientes: abiertas.length,
      totalPendiente: abiertas.fold(0, (s, p) => s + p.total),
      meses: [
        for (var i = 11; i >= 0; i--)
          (
            DateTime(hoy.year, hoy.month - i),
            _periodo(ventas, DateTime(hoy.year, hoy.month - i), finDia(DateTime(hoy.year, hoy.month - i + 1, 0))).vendido,
          ),
      ],
    );
  }

  Future<Reporte> reporte(DateTime desde, DateTime hasta) async {
    _sesion.exigirAdmin();
    final d = inicioDia(desde);
    final h = finDia(hasta);
    bool enRango(DateTime f) => !f.isBefore(d) && !f.isAfter(h);
    final dI = d.toUtc().toIso8601String();
    final hI = h.toUtc().toIso8601String();
    final (todasVentas, consolidadosF, comprasF, gastosF, perdidasF, pagosF, pedidosF) = await (
      _ventas(),
      _s.filas('consolidados', filtro: (q) => q.eq('estado', 'recibido')),
      _s.filas('compras', filtro: (q) => q.gte('fecha', dI).lte('fecha', hI)),
      _s.filas('gastos', filtro: (q) => q.eq('anulado', false).gte('fecha', dI).lte('fecha', hI)),
      _s.filas('movimientos', filtro: (q) => q.eq('tipo', TipoMovimiento.perdida.valor).gte('fecha', dI).lte('fecha', hI)),
      _s.filas('pagos', filtro: (q) => q.eq('anulado', false).gte('fecha', dI).lte('fecha', hI)),
      _s.rpcLista('listar_pedidos'),
    ).wait;

    final ventas = todasVentas.where((v) => enRango(v.fecha)).toList();
    final consolidados = [for (final f in consolidadosF) Consolidado.fromMap(f)].where((c) => enRango(c.fechaRecepcion ?? c.fecha));
    final compras = [for (final f in comprasF) Compra.fromMap(f)];
    final gastos = [for (final f in gastosF) Gasto.fromMap(f)];
    final perdidas = [for (final f in perdidasF) Movimiento.fromMap(f)];
    final pagos = [for (final f in pagosF) Pago.fromMap(f)];
    final pedidos = [for (final f in pedidosF) Pedido.fromMap(f)];

    // Rechazos: pedidos que el local no recibió y productos parciales que no aceptó.
    var perdidoRechazos = 0;
    var cantRechazos = 0;
    final rechazosPorLocal = <String, int>{};
    for (final p in pedidos) {
      final f = p.actualizado ?? p.fecha;
      if (!enRango(f)) continue;
      var n = 0;
      if (p.estado == EstadoPedido.rechazado) {
        perdidoRechazos += p.total;
        n++;
      }
      for (final l in p.lineas.where((l) => l.estado.valor == 'rechazada')) {
        perdidoRechazos += l.totalPedido;
        n++;
      }
      if (n > 0) {
        cantRechazos += n;
        rechazosPorLocal[p.clienteId] = (rechazosPorLocal[p.clienteId] ?? 0) + n;
      }
    }

    final porCategoria = <String, (int, int)>{};
    for (final g in gastos) {
      final x = porCategoria[g.categoria] ?? (0, 0);
      porCategoria[g.categoria] = (x.$1 + 1, x.$2 + g.monto);
    }

    final locales = <String, FilaLocal>{};
    final nombres = {for (final v in ventas) v.clienteId: v.cliente.nombre};
    for (final v in ventas) {
      final x = locales[v.clienteId];
      locales[v.clienteId] = FilaLocal(
        nombre: v.cliente.nombre,
        vendido: (x?.vendido ?? 0) + v.total,
        ganancia: (x?.ganancia ?? 0) + v.ganancia,
        cobrado: 0,
        saldo: (x?.saldo ?? 0) + v.saldo,
        rechazos: rechazosPorLocal[v.clienteId] ?? 0,
      );
    }
    final cobradoPorLocal = <String, int>{};
    for (final p in pagos) {
      cobradoPorLocal[p.clienteId] = (cobradoPorLocal[p.clienteId] ?? 0) + p.monto;
      nombres[p.clienteId] ??= p.clienteNombre;
    }
    final filas = <FilaLocal>[
      for (final id in {...locales.keys, ...cobradoPorLocal.keys})
        FilaLocal(
          nombre: nombres[id] ?? '—',
          vendido: locales[id]?.vendido ?? 0,
          ganancia: locales[id]?.ganancia ?? 0,
          cobrado: cobradoPorLocal[id] ?? 0,
          saldo: locales[id]?.saldo ?? 0,
          rechazos: rechazosPorLocal[id] ?? 0,
        ),
    ]..sort((a, b) => b.vendido.compareTo(a.vendido));

    return Reporte(
      desde: d,
      hasta: h,
      vendido: ventas.fold(0, (s, v) => s + v.total),
      costoVendido: ventas.fold(0, (s, v) => s + v.costoTotal),
      notas: ventas.length,
      pagadoProveedor: consolidados.fold(0, (s, c) => s + c.totalCompra),
      comprasPropias: compras.fold(0, (s, c) => s + c.total),
      gastos: gastos.fold(0, (s, g) => s + g.monto),
      gastosPorCategoria: [for (final e in porCategoria.entries) GastoCategoria(e.key, e.value.$1, e.value.$2)]
        ..sort((a, b) => b.monto.compareTo(a.monto)),
      perdidas: perdidas.fold(0, (s, m) => s + m.valor),
      cobrado: pagos.fold(0, (s, p) => s + p.monto),
      faltaCobrar: ventas.fold(0, (s, v) => s + v.saldo),
      perdidoRechazos: perdidoRechazos,
      cantidadRechazos: cantRechazos,
      descuentos: ventas.fold(0, (s, v) => s + v.lineas.fold(0, (x, l) => x + l.descuento)),
      productos: _porProducto(ventas),
      locales: filas,
    );
  }

  /// Ventas del período (para el detalle del Excel).
  Future<List<Venta>> ventas(DateTime desde, DateTime hasta) async {
    _sesion.exigirAdmin();
    final filas = await _s.filas('ventas', filtro: (q) => q
        .gte('fecha', inicioDia(desde).toUtc().toIso8601String())
        .lte('fecha', finDia(hasta).toUtc().toIso8601String()), orden: 'numero');
    return [for (final f in filas) Venta.fromMap(f)];
  }
}
