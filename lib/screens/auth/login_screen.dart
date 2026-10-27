import 'primer_uso_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/negocio_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/validacion.dart';
import '../../widgets/encabezado_negocio.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  bool _oculta = true;
  bool _cargando = false;
  String? _error;

  /// Bloqueada por 5 intentos fallidos: hasta cuándo (con cuenta regresiva).
  DateTime? _bloqueadaHasta;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _leerBloqueo();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _leerBloqueo() async {
    final hasta = await context.read<AuthProvider>().bloqueoLogin.bloqueadoHasta();
    if (!mounted) return;
    setState(() => _bloqueadaHasta = hasta);
    _reloj?.cancel();
    if (hasta == null) return;
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(_bloqueadaHasta!)) {
        _reloj?.cancel();
        setState(() {
          _bloqueadaHasta = null;
          _error = null;
        });
        _leerBloqueo();
      } else {
        setState(() {});
      }
    });
  }

  String get _falta {
    final resta = _bloqueadaHasta!.difference(DateTime.now());
    return '${resta.inMinutes}:${(resta.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _ingresar() async {
    if (_bloqueadaHasta != null || !_form.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final err = await context.read<AuthProvider>().ingresar(_usuario.text, _clave.text);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _error = err;
      if (err != null) _clave.clear();
    });
    if (err != null) await _leerBloqueo();
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width >= 900;

    final hero = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(28, ancho ? 0 : 36, 28, 28),
          // El mismo encabezado que sale en la factura.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: EncabezadoNegocio(size: ancho ? 64 : 44, soloNombre: true),
            ),
          ),
        ),
      ),
    );

    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Ingresar', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  const Text('Administrador: tu email. Vendedores: el usuario que te dieron.', style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _usuario,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s')), LengthLimitingTextInputFormatter(Largo.email)],
                    decoration: const InputDecoration(
                      labelText: 'Email o usuario',
                      hintText: 'Ej: nombre@gmail.com o juan.perez',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Escribí tu email o usuario';
                      if (t.contains('@')) return validarEmail(t, obligatorio: true);
                      return RegExp(r'^[a-zA-Z0-9._-]{3,30}$').hasMatch(t) ? null : 'Revisá el usuario (ej: juan.perez)';
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _clave,
                    obscureText: _oculta,
                    autofillHints: const [AutofillHints.password],
                    inputFormatters: [LengthLimitingTextInputFormatter(72)],
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _oculta ? 'Mostrar' : 'Ocultar',
                        icon: Icon(_oculta ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _oculta = !_oculta),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Escribí tu contraseña' : null,
                    onFieldSubmitted: (_) => _ingresar(),
                  ),
                  if (_bloqueadaHasta != null)
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_clock_outlined, color: AppColors.red, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('App bloqueada por 5 intentos fallidos.\nPodés volver a intentar en $_falta',
                                style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    )
                  else if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                      child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _cargando || _bloqueadaHasta != null ? null : _ingresar,
                    child: _cargando
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Text(_bloqueadaHasta != null ? 'Bloqueado · $_falta' : 'Ingresar'),
                  ),
                  // Solo la primera vez, mientras no hay ningún administrador
                  // (el servidor igual no deja crear otro si ya hay uno).
                  if (context.watch<NegocioProvider>().tieneAdmin == false) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _cargando ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrimerUsoScreen())),
                      child: const Text('¿Primera vez? Crear el administrador'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (ancho) return Scaffold(body: Row(children: [Expanded(flex: 5, child: hero), Expanded(flex: 4, child: form)]));
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(
              children: [
                SizedBox(height: 200, width: double.infinity, child: hero),
                form,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
