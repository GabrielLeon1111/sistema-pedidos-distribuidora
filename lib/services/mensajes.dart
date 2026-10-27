import '../models/consolidado.dart';
import '../models/pago.dart';
import '../models/pedido.dart';
import '../models/venta.dart';
import '../utils/formato.dart';

// Mensajes automáticos que acompañan cada documento cuando se manda por WhatsApp.

/// Va al final de los mensajes a los locales.
const avisoAutomatico = '\n\nEste es un mensaje automático enviado por el sistema, no hace falta que responda.';

String _saludo(String? nombre) {
  final n = nombre?.trim() ?? '';
  return n.isEmpty ? 'Hola!' : 'Hola $n!';
}

/// Al local: su nota de pedido (o la nota ajustada si llegó una parte).
String mensajePedido(Pedido p, String negocio) {
  final ajustada = p.lineas.any((l) => l.cambioCantidad);
  return '${_saludo(p.cliente.contacto ?? p.cliente.nombre)} '
      '${ajustada ? 'Te reenviamos tu nota de pedido N° ${nroDoc(p.numero)} ajustada a lo que llegó' : 'Te enviamos tu nota de pedido N° ${nroDoc(p.numero)}'} '
      'de $negocio por ${gs(p.total)}. ¡Gracias!$avisoAutomatico';
}

String mensajeVenta(Venta v, String negocio) {
  final saldo = v.saldo > 0 ? ' Queda un saldo de ${gs(v.saldo)}.' : ' Está todo pagado.';
  final doc = v.factura == null ? 'nota de venta N° ${nroDoc(v.numero)}' : 'factura N° ${v.factura!.numeroCompleto}';
  return '${_saludo(v.cliente.contacto ?? v.cliente.nombre)} Te enviamos tu $doc '
      'de $negocio por ${gs(v.total)}.$saldo ¡Muchas gracias!$avisoAutomatico';
}

String mensajeRecibo(Pago p, String negocio, {int? saldo}) =>
    '${_saludo(p.clienteNombre)} Te enviamos el recibo N° ${nroDoc(p.numero)} de $negocio por ${gs(p.monto)}.'
    '${saldo == null ? '' : saldo > 0 ? ' Saldo pendiente: ${gs(saldo)}.' : ' No queda saldo pendiente.'} ¡Gracias!$avisoAutomatico';

/// Al proveedor: la hoja con todo lo del día.
String mensajeProveedor(Consolidado c, String negocio) =>
    '${_saludo(c.proveedorNombre)} Te paso el pedido de $negocio del ${fechaCorta.format(c.fecha)} '
    '(${c.lineas.length} productos). Por favor confirmame precios y disponibilidad. ¡Gracias!';

/// Al local que debe: recordatorio amable.
String mensajeDeuda(String local, int deuda, String negocio) =>
    '${_saludo(local)} Te escribimos de $negocio para recordarte que tenés un saldo pendiente de ${gs(deuda)}. ¡Gracias!$avisoAutomatico';
