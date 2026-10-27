import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/marca.dart';
import 'login_screen.dart';

/// Después de entrar con usuario y contraseña, ofrece activar la huella /
/// Face ID (solo si el celular la tiene).
Future<void> ofrecerBiometria(BuildContext context) async {
  final b = context.read<AuthProvider>().biometria;
  if (await b.activada() || !await b.disponible() || !context.mounted) return;
  final quiere = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.fingerprint, size: 40),
      title: const Text('¿Activar huella / Face ID?'),
      content: const Text('La próxima vez vas a poder entrar más rápido, sin escribir tu contraseña.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ahora no')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Activar')),
      ],
    ),
  );
  if (quiere == true) await b.activar(true);
}

/// Pide la huella / Face ID antes de entrar (sesión ya abierta en este equipo).
/// Si no funciona, se puede entrar con usuario y contraseña.
class BloqueoScreen extends StatefulWidget {
  const BloqueoScreen({super.key});

  @override
  State<BloqueoScreen> createState() => _BloqueoScreenState();
}

class _BloqueoScreenState extends State<BloqueoScreen> {
  bool _verificando = false;
  bool _fallo = false;
  bool _manual = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _intentar());
  }

  Future<void> _intentar() async {
    if (_verificando) return;
    setState(() {
      _verificando = true;
      _fallo = false;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.biometria.disponible() && await auth.biometria.verificar();
    if (!mounted) return;
    if (ok) {
      auth.desbloquear();
    } else {
      setState(() {
        _verificando = false;
        _fallo = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_manual) return const LoginScreen();
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Marca(size: 40, color: Colors.white),
                  const SizedBox(height: 40),
                  InkWell(
                    borderRadius: BorderRadius.circular(60),
                    onTap: _verificando ? null : _intentar,
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                      child: const Icon(Icons.fingerprint, size: 64, color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _verificando
                        ? 'Verificando…'
                        : _fallo
                            ? 'No se pudo verificar tu huella / Face ID'
                            : 'Tocá para desbloquear',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 28),
                  if (!_verificando && _fallo) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.ink,
                      ),
                      onPressed: _intentar,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Intentar de nuevo'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextButton(
                    onPressed: () => setState(() => _manual = true),
                    child: const Text('Usar usuario y contraseña', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
