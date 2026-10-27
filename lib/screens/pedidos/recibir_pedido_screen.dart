import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/clave_operacion.dart';
import '../../models/pedido.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/pedido_repository.dart';
import '../../repositories/producto_repository.dart';
import '../../security/registro_seguro.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import 'entrega_screen.dart';

/// Llegó la mercadería de una nota (sin hoja del proveedor): se pone lo que
/// se pagó por cada producto y se pasa a la entrega, que la convierte en venta.
class RecibirPedidoScreen extends StatefulWidget {
  const RecibirPedidoScreen({super.key, required this.pedido, this.sena = 0});
  final Pedido pedido;
  final int sena;

  @override
  State<RecibirPedidoScreen> createState() => _RecibirPedidoScreenState();
}

class _RecibirPedidoScreenState extends State<RecibirPedidoScreen> {
  final _form = GlobalKey<FormState>();
  final _clave = ClaveOperacion();
  late final _lineas = widget.pedido.lineasAProveedor.toList();
  late final _costos = {for (final l in _lineas) l.id: TextEditingController()};
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // Se sugiere el último precio de compra (por la forma: docena, caja...).
    context.read<ProductoRepository>().listar(incluirInactivos: true).then((ps) {
      if (!mounted) return;
      setState(() {
        for (final l in _lineas) {
          final p = ps.where((x) => x.id == l.productoId).firstOrNull;
          final c = p == null ? 0 : (p.precioCompra * l.factor).round();
          if (c > 0 && _costos[l.id]!.text.isEmpty) _costos[l.id]!.text = miles(c);
        }
      });
    });
  }

  @override
  void dispose() {
    for (final c in _costos.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, int> get _valores => {
        for (final l in _lineas)
          if ((leerMonto(_costos[l.id]!.text) ?? 0) > 0) l.id: leerMonto(_costos[l.id]!.text)!,
      };

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final p = await context.read<PedidoRepository>().recibir(widget.pedido.id, _valores, clave: _clave.valor);
      _clave.renovar();
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      showSnack(context, 'Mercadería recibida: ahora entregala y queda la venta');
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => EntregaScreen(pedido: p, sena: widget.sena)));
    } catch (e) {
      registrarError('recibirPedido', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    return Scaffold(
      appBar: AppBar(title: Text('Llegó el pedido N° ${nroDoc(p.numero)}')),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: EdgeInsets.fromLTRB(margenLateral(context), 8, margenLateral(context), 120),
          children: [
            Cuerpo(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(p.cliente.nombre, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('Poné cuánto pagaste por cada producto. Después la entregás y queda la venta con su factura.'),
                const SectionTitle('Precio de compra'),
                for (final l in _lineas)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(l.descripcion, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          ['${cantidad(l.cantidad)} ${l.unidadTexto()} × ${gs(l.precio)}', if (l.nota != null) l.nota!].join(' · '),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        MontoField(
                          controller: _costos[l.id]!,
                          label: 'Pagaste por ${l.unidad} *',
                          validator: validarMonto(campo: 'el precio de compra'),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.point_of_sale),
            label: Text(_guardando ? 'Guardando…' : 'Recibido: pasar a la venta'),
          ),
        ),
      ),
    );
  }
}
