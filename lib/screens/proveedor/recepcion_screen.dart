import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/clave_operacion.dart';
import '../../models/consolidado.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/producto_repository.dart';
import '../../repositories/proveedor_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/filtro_categorias.dart';

/// Recepción: por cada producto, si llegó completo, una parte o no llegó, y el
/// precio de compra (ya trae el último que se pagó).
/// En una lista de compras (la compra la hace uno mismo) es lo mismo, pero se
/// va marcando mientras se compra: qué se compró, qué no y cuánto se pagó.
/// Lo marcado se guarda en el teléfono a medida que se marca.
class RecepcionScreen extends StatefulWidget {
  const RecepcionScreen({super.key, required this.consolidado});
  final Consolidado consolidado;

  @override
  State<RecepcionScreen> createState() => _RecepcionScreenState();
}

class _Marca {
  _Marca(LineaConsolidado l, {required bool compra})
      : estado = compra ? EstadoRecepcion.pendiente : EstadoRecepcion.completo,
        precio = TextEditingController(text: l.precioCompra > 0 ? miles(l.precioCompra) : ''),
        recibido = TextEditingController(),
        reparto = {for (final d in l.detalle) d.lineaId: TextEditingController()};

  /// En la lista de compras arranca sin marcar.
  EstadoRecepcion estado;
  final TextEditingController precio;
  final TextEditingController recibido;
  final Map<String, TextEditingController> reparto;

  Map<String, dynamic> toMap() => {
        'e': estado.valor,
        'r': recibido.text,
        'p': precio.text,
        'rep': {for (final e in reparto.entries) e.key: e.value.text},
      };

  void cargar(Map<String, dynamic> m) {
    estado = EstadoRecepcion.de(m['e'] as String?);
    recibido.text = (m['r'] as String?) ?? '';
    precio.text = (m['p'] as String?) ?? precio.text;
    final r = m['rep'];
    if (r is Map) {
      for (final e in r.entries) {
        reparto[e.key]?.text = '${e.value}';
      }
    }
  }

  void dispose() {
    precio.dispose();
    recibido.dispose();
    for (final c in reparto.values) {
      c.dispose();
    }
  }
}

class _RecepcionScreenState extends State<RecepcionScreen> {
  final _form = GlobalKey<FormState>();
  late final bool _compra = widget.consolidado.directa;
  late final List<_Marca> _marcas = [for (final l in widget.consolidado.lineas) _Marca(l, compra: _compra)];
  String get _kBorrador => 'borrador_recepcion_${widget.consolidado.id}';
  bool _guardando = false;

  /// La misma en cada reintento: si se corta la señal, la mercadería no entra dos veces.
  final _clave = ClaveOperacion();

  /// Categoría de cada producto (por id): los productos se muestran separados por categoría.
  Map<String, String?> _categorias = const {};

  /// Lo marcado hasta ahora (si se salió de la pantalla a mitad de la compra).
  Future<void> _cargarBorrador() async {
    try {
      final txt = (await SharedPreferences.getInstance()).getString(_kBorrador);
      if (txt == null || !mounted) return;
      final lista = jsonDecode(txt) as List;
      if (lista.length != _marcas.length) return;
      setState(() {
        for (var i = 0; i < lista.length; i++) {
          _marcas[i].cargar(Map<String, dynamic>.from(lista[i] as Map));
        }
      });
    } catch (e) {
      registrarError('borradorRecepcion', e);
    }
  }

  void _guardarBorrador() {
    final txt = jsonEncode([for (final m in _marcas) m.toMap()]);
    SharedPreferences.getInstance().then((p) => p.setString(_kBorrador, txt)).catchError((Object e) {
      registrarError('guardarBorradorRecepcion', e);
      return false;
    });
  }

  void _marcar(_Marca m, EstadoRecepcion e) {
    setState(() => m.estado = e);
    _guardarBorrador();
  }

  int get _marcados => _marcas.where((m) => m.estado != EstadoRecepcion.pendiente).length;

  @override
  void initState() {
    super.initState();
    _cargarBorrador();
    context.read<ProductoRepository>().listar(incluirInactivos: true).then((ps) {
      if (mounted) setState(() => _categorias = {for (final p in ps) p.id: p.categoria});
    }).catchError((Object e) => registrarError('categoriasRecepcion', e));
  }

  String _categoria(LineaConsolidado l) => (l.productoId == null ? null : _categorias[l.productoId]) ?? sinCategoria;

  /// Productos que llegaron y no tienen precio de compra.
  List<String> get _faltanPrecio => [
        for (var i = 0; i < _marcas.length; i++)
          if (_marcas[i].estado != EstadoRecepcion.noLlego &&
              _marcas[i].estado != EstadoRecepcion.pendiente &&
              (leerMonto(_marcas[i].precio.text) ?? 0) <= 0)
            widget.consolidado.lineas[i].descripcion,
      ];

  @override
  void dispose() {
    for (final m in _marcas) {
      m.dispose();
    }
    super.dispose();
  }

  /// Al escribir cuánto llegó, se reparte solo entre los locales (se puede cambiar a mano).
  void _sugerirReparto(int i) {
    final l = widget.consolidado.lineas[i];
    final q = leerCantidad(_marcas[i].recibido.text) ?? 0;
    final r = repartoSugerido(l.detalle, q);
    for (final d in l.detalle) {
      _marcas[i].reparto[d.lineaId]!.text = cantidad(r[d.lineaId] ?? 0);
    }
  }

  int get _total {
    var t = 0;
    for (var i = 0; i < _marcas.length; i++) {
      final l = widget.consolidado.lineas[i];
      final m = _marcas[i];
      final q = switch (m.estado) {
        EstadoRecepcion.completo => l.cantidad,
        EstadoRecepcion.parcial => leerCantidad(m.recibido.text) ?? 0,
        _ => 0.0,
      };
      t += (q * (leerMonto(m.precio.text) ?? 0)).round();
    }
    return t;
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final sinMarcar = [
      for (var i = 0; i < _marcas.length; i++)
        if (_marcas[i].estado == EstadoRecepcion.pendiente) widget.consolidado.lineas[i].descripcion,
    ];
    if (sinMarcar.isNotEmpty) {
      showSnack(context, 'Te falta marcar: ${sinMarcar.join(', ')}', error: true);
      return;
    }
    // La lista se arma de a poco: algo que no se ve en pantalla puede no estar revisado.
    final faltan = _faltanPrecio;
    if (faltan.isNotEmpty) {
      showSnack(context, 'Falta el precio de compra de: ${faltan.join(', ')}', error: true);
      return;
    }
    final marcas = <int, MarcaRecepcion>{};
    for (var i = 0; i < _marcas.length; i++) {
      final m = _marcas[i];
      marcas[i] = MarcaRecepcion(
        estado: m.estado,
        cantidadRecibida: leerCantidad(m.recibido.text) ?? 0,
        precioCompra: leerMonto(m.precio.text) ?? 0,
        // Un solo local: se le da todo lo que llegó (el reparto lo arma el repositorio).
        reparto: m.estado == EstadoRecepcion.parcial && m.reparto.length > 1
            ? {for (final e in m.reparto.entries) e.key: leerCantidad(e.value.text) ?? 0}
            : const {},
      );
    }
    final ok = await confirmar(
      context,
      titulo: _compra ? 'Terminar la compra' : 'Confirmar recepción',
      mensaje: _compra
          ? 'Gastaste ${gs(_total)}. Lo que no conseguiste se quita de las notas, y lo que compraste en parte queda esperando que cada local confirme.'
          : 'Se paga ${gs(_total)} al proveedor. Lo que no llegó se anula en los pedidos, y lo que llegó en parte queda esperando que cada local confirme.',
      si: _compra ? 'Terminar' : 'Confirmar',
    );
    if (!ok || !mounted) return;
    setState(() => _guardando = true);
    try {
      await context.read<ProveedorRepository>().registrarRecepcion(widget.consolidado.id, marcas, clave: _clave.valor);
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      SharedPreferences.getInstance().then((p) => p.remove(_kBorrador)).ignore();
      showSnack(context, _compra ? 'Compra registrada: las notas quedan listas para entregar' : 'Recepción registrada');
      Navigator.pop(context);
    } catch (e) {
      registrarError('recepcion', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.consolidado;
    // Separados por categoría: el título de cada una y debajo sus productos.
    final filas = <Object>[
      for (final cat in categoriasDe(c.lineas.map(_categoria))) ...[
        cat,
        for (var i = 0; i < c.lineas.length; i++)
          if (_categoria(c.lineas[i]) == cat) i,
      ],
    ];
    final variasCategorias = filas.whereType<String>().length > 1;
    return Scaffold(
      appBar: AppBar(title: Text(_compra ? 'Mi lista de compras' : 'Recepción · ${c.proveedorNombre}')),
      body: Form(
        key: _form,
        onChanged: () {
          setState(() {});
          _guardarBorrador();
        },
        child: ListView.separated(
          padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 140),
          itemCount: filas.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, k) {
            final fila = filas[k];
            if (fila is String) {
              if (!variasCategorias) return const SizedBox.shrink();
              final n = filas.skip(k + 1).takeWhile((x) => x is int).length;
              return Cuerpo(maxWidth: 720, child: SectionTitle('$fila ($n)'));
            }
            final i = fila as int;
            final l = c.lineas[i];
            final m = _marcas[i];
            return Cuerpo(
              maxWidth: 720,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text(l.descripcion, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                      Text('${_compra ? 'Comprar' : 'Pedido'}: ${cantidad(l.cantidad)} ${textoForma(l.unidad, l.factor, l.cantidad)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    if (l.nota != null) Text(l.nota!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 10),
                    SegmentedButton<EstadoRecepcion>(
                      showSelectedIcon: false,
                      emptySelectionAllowed: true,
                      segments: [
                        ButtonSegment(value: EstadoRecepcion.completo, label: Text(_compra ? 'Compré todo' : 'Completo')),
                        const ButtonSegment(value: EstadoRecepcion.parcial, label: Text('Una parte')),
                        ButtonSegment(value: EstadoRecepcion.noLlego, label: Text(_compra ? 'No conseguí' : 'No llegó')),
                      ],
                      selected: m.estado == EstadoRecepcion.pendiente ? const {} : {m.estado},
                      onSelectionChanged: (v) => _marcar(m, v.isEmpty ? EstadoRecepcion.pendiente : v.first),
                    ),
                    if (m.estado != EstadoRecepcion.noLlego && m.estado != EstadoRecepcion.pendiente) ...[
                      const SizedBox(height: 12),
                      FilaCampos(anchoMinimo: 420, children: [
                        if (m.estado == EstadoRecepcion.parcial) ...[
                          Expanded(
                            child: CantidadField(
                              controller: m.recibido,
                              label: _compra ? 'Cuánto compré *' : 'Cuánto llegó *',
                              onChanged: (_) => setState(() => _sugerirReparto(i)),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: MontoField(
                            controller: m.precio,
                            label: _compra ? 'Pagué (por ${l.unidad}) *' : 'Precio de compra *',
                            helper: l.precioCompra > 0 ? 'Último: ${gs(l.precioCompra)}. Cambialo solo si subió o bajó.' : null,
                            validator: validarPrecio,
                          ),
                        ),
                      ]),
                    ],
                    if (m.estado == EstadoRecepcion.parcial && l.detalle.length > 1) ...[
                      const SizedBox(height: 12),
                      const Text('Reparto entre los locales', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      for (final d in l.detalle)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Expanded(child: Text('${d.clienteNombre} (pidió ${cantidad(d.cantidad)})')),
                            SizedBox(
                              width: 96,
                              child: TextFormField(
                                controller: m.reparto[d.lineaId],
                                textAlign: TextAlign.right,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(isDense: true),
                                validator: (v) {
                                  final q = leerCantidad(v ?? '') ?? -1;
                                  if (q < 0) return 'Revisá';
                                  if (q > d.cantidad + 0.0001) return 'Máx. ${cantidad(d.cantidad)}';
                                  return null;
                                },
                              ),
                            ),
                          ]),
                        ),
                    ],
                    if (m.estado == EstadoRecepcion.parcial && l.detalle.length == 1) ...[
                      const SizedBox(height: 8),
                      Text('Todo va a ${l.detalle.single.clienteNombre}.', style: const TextStyle(color: AppColors.muted)),
                    ],
                    if (m.estado == EstadoRecepcion.noLlego) ...[
                      const SizedBox(height: 8),
                      Text('${_compra ? 'No se consiguió: se quita de' : 'Se anula en'} ${l.detalle.length == 1 ? 'el pedido de ${l.detalle.single.clienteNombre}' : 'los ${l.detalle.length} pedidos'}.',
                          style: const TextStyle(color: AppColors.red)),
                    ],
                  ]),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_compra)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Marcaste $_marcados de ${_marcas.length} productos',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _marcados == _marcas.length ? AppColors.green : AppColors.muted)),
              ),
            TotalDestacado(etiqueta: _compra ? 'GASTADO EN LA COMPRA' : 'A PAGAR AL PROVEEDOR', monto: _total),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: const Icon(Icons.check),
                label: Text(_guardando ? 'Guardando…' : (_compra ? 'Terminar la compra' : 'Confirmar recepción')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

String? validarPrecio(String? v) {
  final n = leerMonto(v ?? '');
  if (n == null || n <= 0) return 'Poné el precio de compra';
  return null;
}
