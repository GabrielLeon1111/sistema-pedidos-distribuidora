import '../data/servidor.dart';
import '../data/sesion.dart';
import '../models/consolidado.dart';
import '../models/historial.dart';
import '../models/pago.dart';
import '../models/pedido.dart';
import '../models/venta.dart';
import '../utils/formato.dart';

enum TipoDocumento {
  notaPedido('Nota de pedido'),
  notaVenta('Nota de venta'),
  consolidado('Consolidado'),
  recepcion('Recepción'),
  recibo('Recibo');

  const TipoDocumento(this.texto);
  final String texto;
}

/// Un documento guardado (se haya enviado o no), para volver a abrirlo.
class Documento {
  final TipoDocumento tipo;
  final String id;
  final int numero;
  final DateTime fecha;
  final String titulo;
  final String detalle;
  final int? monto;
  final bool anulado;

  const Documento({
    required this.tipo,
    required this.id,
    required this.numero,
    required this.fecha,
    required this.titulo,
    required this.detalle,
    this.monto,
    this.anulado = false,
  });
}

class HistorialRepository {
  HistorialRepository(this._s, this._sesion);
  final Servidor _s;
  final Sesion _sesion;

  /// Registro de cambios (quién hizo qué). SELECT historial (solo el administrador).
  Future<List<Cambio>> cambios({DateTime? desde, DateTime? hasta, String? area, String? usuario, bool soloImportantes = false}) async {
    _sesion.exigirAdmin();
    final filas = await _s.filas('historial', filtro: (q) {
      var r = q;
      if (desde != null) r = r.gte('fecha', desde.toUtc().toIso8601String());
      if (hasta != null) r = r.lte('fecha', hasta.toUtc().toIso8601String());
      if (area != null) r = r.eq('area', area);
      if (usuario != null) r = r.eq('usuario_nombre', usuario);
      if (soloImportantes) r = r.eq('importante', true);
      return r;
    }, orden: 'fecha', ascendente: false);
    return [for (final f in filas) Cambio.fromMap(f)];
  }

  Future<List<String>> personas() async {
    _sesion.exigirAdmin();
    final filas = await _s.filas('historial');
    return {for (final f in filas) (f['usuario_nombre'] as String?) ?? 'Sistema'}.toList()..sort();
  }

  /// Todos los documentos (notas, consolidados, recepciones y recibos).
  Future<List<Documento>> documentos({TipoDocumento? tipo, String? buscar}) async {
    final u = _sesion.exigirUsuario();
    final r = <Documento>[];
    bool quiere(TipoDocumento t) => tipo == null || tipo == t;
    if (quiere(TipoDocumento.notaPedido)) {
      for (final p in [for (final f in await _s.rpcLista('listar_pedidos')) Pedido.fromMap(f)]) {
        r.add(Documento(
          tipo: TipoDocumento.notaPedido,
          id: p.id,
          numero: p.numero,
          fecha: p.fecha,
          titulo: p.cliente.nombre,
          detalle: '${p.estado.texto}${p.vendedorNombre == null ? '' : ' · ${p.vendedorNombre}'}',
          monto: p.total,
          anulado: p.estado == EstadoPedido.anulado,
        ));
      }
    }
    if (u.esAdmin) {
      if (quiere(TipoDocumento.notaVenta)) {
        for (final f in await _s.filas('ventas')) {
          final v = Venta.fromMap(f);
          r.add(Documento(
            tipo: TipoDocumento.notaVenta,
            id: v.id,
            numero: v.numero,
            fecha: v.fecha,
            titulo: v.cliente.nombre,
            detalle: v.estadoPago.texto + (v.saldo > 0 ? ' · debe ${gs(v.saldo)}' : ''),
            monto: v.total,
            anulado: v.anulada,
          ));
        }
      }
      if (quiere(TipoDocumento.consolidado) || quiere(TipoDocumento.recepcion)) {
        for (final f in await _s.filas('consolidados')) {
          final c = Consolidado.fromMap(f);
          if (quiere(TipoDocumento.consolidado)) {
            r.add(Documento(
              tipo: TipoDocumento.consolidado,
              id: c.id,
              numero: c.numero,
              fecha: c.fecha,
              titulo: c.proveedorNombre,
              detalle: '${c.lineas.length} productos · ${c.pedidoIds.length} pedidos${c.anulado ? ' · Anulado: ${c.motivo ?? ''}' : ''}',
              anulado: c.anulado,
            ));
          }
          if (c.recibido && quiere(TipoDocumento.recepcion)) {
            r.add(Documento(
              tipo: TipoDocumento.recepcion,
              id: c.id,
              numero: c.numero,
              fecha: c.fechaRecepcion ?? c.fecha,
              titulo: c.proveedorNombre,
              detalle: 'Recibido por ${c.recibidoPor ?? '—'}',
              monto: c.totalCompra,
            ));
          }
        }
      }
      if (quiere(TipoDocumento.recibo)) {
        for (final f in await _s.filas('pagos')) {
          final p = Pago.fromMap(f);
          r.add(Documento(
            tipo: TipoDocumento.recibo,
            id: p.id,
            numero: p.numero,
            fecha: p.fecha,
            titulo: p.clienteNombre,
            detalle: '${metodoPagoTexto(p.metodo)}${p.esSena ? ' · seña' : ''}',
            monto: p.monto,
            anulado: p.anulado,
          ));
        }
      }
    }
    final q = buscar?.trim().toLowerCase() ?? '';
    final filtrados = q.isEmpty
        ? r
        : r.where((d) => d.titulo.toLowerCase().contains(q) || nroDoc(d.numero).contains(q) || '${d.numero}' == q).toList();
    filtrados.sort((a, b) => b.fecha.compareTo(a.fecha));
    return filtrados;
  }
}
