import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/usuario.dart';
import '../../providers/auth_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/usuario_repository.dart';
import '../../security/claves.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';

/// Vendedores y administradores: alta, contraseña y activar/desactivar.
class UsuariosScreen extends StatelessWidget {
  const UsuariosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final yo = context.watch<AuthProvider>().usuario?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nuevo-usuario',
        onPressed: () => _nuevo(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Usuario'),
      ),
      body: ReloadingFuture<List<Usuario>>(
        contexto: 'usuarios',
        load: () => context.read<UsuarioRepository>().listar(),
        builder: (context, lista, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: EdgeInsets.fromLTRB(margenLateral(context), 4, margenLateral(context), 100),
            children: [
              Cuerpo(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Aviso(
                    'El vendedor solo ve pedidos y clientes: no ve costos, márgenes ni reportes.',
                    color: AppColors.blue,
                    fondo: AppColors.blueSoft,
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Column(children: [
                      for (var i = 0; i < lista.length; i++) ...[
                        if (i > 0) const Divider(),
                        _FilaUsuario(u: lista[i], soyYo: lista[i].id == yo),
                      ],
                    ]),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _nuevo(BuildContext context) async {
    final creado = await showDialog<bool>(context: context, builder: (_) => const _NuevoUsuario());
    if (creado == true && context.mounted) {
      context.read<RefreshBus>().changed();
      showSnack(context, 'Usuario creado. Pasale su usuario y contraseña.');
    }
  }
}

class _FilaUsuario extends StatelessWidget {
  const _FilaUsuario({required this.u, required this.soyYo});
  final Usuario u;
  final bool soyYo;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(
          backgroundColor: u.activo ? (u.esAdmin ? AppColors.accentSoft : AppColors.primarySoft) : AppColors.line,
          child: Icon(u.esAdmin ? Icons.admin_panel_settings_outlined : Icons.person_outline, color: u.activo ? AppColors.ink : AppColors.muted),
        ),
        title: Text(soyYo ? '${u.nombre} (vos)' : u.nombre, style: TextStyle(color: u.activo ? null : AppColors.muted)),
        subtitle: Text('${u.usuario} · ${u.rolTexto} · desde ${fechaCorta.format(u.creado)}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!u.activo) const Pill('Desactivado', color: AppColors.red, background: AppColors.redSoft),
          PopupMenuButton<String>(
            onSelected: (op) => op == 'clave' ? _cambiarClave(context) : _activar(context),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clave', child: Text('Poner contraseña nueva')),
              if (!soyYo) PopupMenuItem(value: 'activo', child: Text(u.activo ? 'Desactivar' : 'Activar')),
            ],
          ),
        ]),
      );

  Future<void> _activar(BuildContext context) async {
    if (u.activo) {
      final ok = await confirmar(
        context,
        titulo: '¿Desactivar a ${u.nombre}?',
        mensaje: 'No va a poder entrar a la app. Sus pedidos y documentos quedan guardados.',
        si: 'Desactivar',
        peligro: true,
      );
      if (!ok || !context.mounted) return;
    }
    final repo = context.read<UsuarioRepository>();
    final bus = context.read<RefreshBus>();
    final hecho = await runSafe(context, 'activarUsuario', () => repo.activar(u.id, !u.activo), ok: u.activo ? 'Usuario desactivado' : 'Usuario activado');
    if (hecho) bus.changed();
  }

  Future<void> _cambiarClave(BuildContext context) async {
    final ctrl = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Contraseña nueva para ${u.nombre}'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña nueva'),
            validator: validarClave,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => form.currentState!.validate() ? Navigator.pop(c, true) : null, child: const Text('Cambiar')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await runSafe(context, 'cambiarClaveUsuario', () => context.read<UsuarioRepository>().cambiarClave(u.id, ctrl.text), ok: 'Contraseña cambiada');
    }
    ctrl.dispose();
  }
}

class _NuevoUsuario extends StatefulWidget {
  const _NuevoUsuario();

  @override
  State<_NuevoUsuario> createState() => _NuevoUsuarioState();
}

class _NuevoUsuarioState extends State<_NuevoUsuario> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  String _rol = 'vendedor';
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [_nombre, _usuario, _clave]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _crear() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final ok = await runSafe(
      context,
      'crearUsuario',
      () => context.read<UsuarioRepository>().crear(nombre: _nombre.text, usuario: _usuario.text, clave: _clave.text, rol: _rol),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nuevo usuario'),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _nombre,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                inputFormatters: formatoTexto(Largo.nombre),
                decoration: const InputDecoration(labelText: 'Nombre y apellido *'),
                validator: validarTexto(campo: 'el nombre', obligatorio: true, min: 3, max: Largo.nombre),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usuario,
                autocorrect: false,
                inputFormatters: formatoTexto(30),
                decoration: const InputDecoration(labelText: 'Usuario para entrar *', hintText: 'Ej: juan.perez'),
                validator: (v) => RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch((v ?? '').trim().toLowerCase())
                    ? null
                    : 'De 3 a 30 letras, números, punto o guion',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clave,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña *'),
                validator: validarClave,
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'vendedor', label: Text('Vendedor'), icon: Icon(Icons.person_outline)),
                  ButtonSegment(value: 'admin', label: Text('Administrador'), icon: Icon(Icons.admin_panel_settings_outlined)),
                ],
                selected: {_rol},
                onSelectionChanged: (s) => setState(() => _rol = s.first),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: _guardando ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: _guardando ? null : _crear, child: Text(_guardando ? 'Creando…' : 'Crear')),
        ],
      );
}
