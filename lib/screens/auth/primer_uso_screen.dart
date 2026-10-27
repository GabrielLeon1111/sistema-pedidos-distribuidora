import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../security/claves.dart';
import '../../theme/app_theme.dart';
import '../../utils/validacion.dart';

/// La primera vez que se abre la app: se crea el usuario administrador.
class PrimerUsoScreen extends StatefulWidget {
  const PrimerUsoScreen({super.key});

  @override
  State<PrimerUsoScreen> createState() => _PrimerUsoScreenState();
}

class _PrimerUsoScreenState extends State<PrimerUsoScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  final _repetir = TextEditingController();
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _usuario.dispose();
    _clave.dispose();
    _repetir.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final err = await context.read<AuthProvider>().crearPrimerAdmin(
          nombre: _nombre.text,
          usuario: _usuario.text,
          clave: _clave.text,
        );
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.storefront_rounded, size: 34, color: AppColors.primary),
                      ),
                      const SizedBox(height: 18),
                      Text('¡Bienvenido!', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      const Text(
                        'Es la primera vez que se abre la app. Creá el usuario administrador: '
                        'con él vas a ver todo y crear los usuarios de los vendedores.',
                        style: TextStyle(color: AppColors.muted, fontSize: 15),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _nombre,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: formatoTexto(Largo.nombre),
                        decoration: const InputDecoration(labelText: 'Nombre y apellido *', prefixIcon: Icon(Icons.badge_outlined)),
                        validator: validarTexto(campo: 'tu nombre', obligatorio: true, min: 3, max: Largo.nombre),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _usuario,
                        autocorrect: false,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')), LengthLimitingTextInputFormatter(30)],
                        decoration: const InputDecoration(
                          labelText: 'Usuario para ingresar *',
                          hintText: 'Ej: maria.gomez',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (v) => RegExp(r'^[a-zA-Z0-9._-]{3,30}$').hasMatch((v ?? '').trim())
                            ? null
                            : 'Mínimo 3 letras o números (se puede usar punto)',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _clave,
                        obscureText: true,
                        inputFormatters: [LengthLimitingTextInputFormatter(72)],
                        decoration: const InputDecoration(labelText: 'Contraseña *', prefixIcon: Icon(Icons.lock_outline_rounded)),
                        validator: validarClave,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _repetir,
                        obscureText: true,
                        inputFormatters: [LengthLimitingTextInputFormatter(72)],
                        decoration: const InputDecoration(labelText: 'Repetí la contraseña *', prefixIcon: Icon(Icons.lock_outline_rounded)),
                        validator: (v) => v != _clave.text ? 'No coincide con la contraseña' : null,
                        onFieldSubmitted: (_) => _crear(),
                      ),
                      if (_error != null)
                        Container(
                          margin: const EdgeInsets.only(top: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                          child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _cargando ? null : _crear,
                        child: _cargando
                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : const Text('Crear y entrar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
