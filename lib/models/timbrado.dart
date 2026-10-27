import '../utils/formato.dart';
import 'json.dart';

/// Timbrado de la SET para emitir facturas: número, vigencia, establecimiento,
/// punto de expedición y rango de numeración.
class Timbrado {
  final String id;

  /// Número de timbrado (8 dígitos).
  final String numero;
  final DateTime inicio;
  final DateTime fin;

  /// Código de establecimiento (ej: "001").
  final String establecimiento;

  /// Punto de expedición (ej: "001").
  final String punto;
  final int desde;
  final int hasta;

  /// Próximo número de factura a emitir.
  final int siguiente;
  final bool activo;
  final DateTime creado;

  /// Pie impreso de la imprenta (habilitación, imprenta, RUC, cantidad de
  /// talonarios, rango y fecha), tal como sale al pie del talonario.
  final String? pieImprenta;

  const Timbrado({
    required this.id,
    required this.numero,
    required this.inicio,
    required this.fin,
    this.establecimiento = '001',
    this.punto = '001',
    this.desde = 1,
    this.hasta = 9999999,
    this.siguiente = 1,
    this.activo = true,
    required this.creado,
    this.pieImprenta,
  });

  /// Vigente hoy (y con números disponibles).
  bool vigenteEn(DateTime d) => !d.isBefore(inicioDia(inicio)) && !d.isAfter(finDia(fin));
  bool get vigente => vigenteEn(DateTime.now());
  bool get agotado => siguiente > hasta;
  int get disponibles => (hasta - siguiente + 1).clamp(0, hasta);

  String get estadoTexto {
    if (!activo) return 'Inactivo';
    if (agotado) return 'Sin números';
    if (DateTime.now().isBefore(inicioDia(inicio))) return 'Todavía no vigente';
    if (!vigente) return 'Vencido';
    return 'Vigente';
  }

  factory Timbrado.fromMap(Map<String, dynamic> m) => Timbrado(
        id: m['id'] as String,
        numero: m['numero'] as String,
        inicio: toDate(m['inicio']),
        fin: toDate(m['fin']),
        establecimiento: (m['establecimiento'] as String?) ?? '001',
        punto: (m['punto'] as String?) ?? '001',
        desde: toInt(m['desde']),
        hasta: toInt(m['hasta']),
        siguiente: toInt(m['siguiente']),
        activo: m['activo'] != false,
        creado: toDate(m['creado']),
        pieImprenta: textOrNull(m['pie_imprenta']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'numero': numero,
        'inicio': fechaIsoDia(inicio),
        'fin': fechaIsoDia(fin),
        'establecimiento': establecimiento,
        'punto': punto,
        'desde': desde,
        'hasta': hasta,
        'siguiente': siguiente,
        'activo': activo,
        'creado': creado.toIso8601String(),
        'pie_imprenta': textOrNull(pieImprenta),
      };
}

/// "001-001 0001481"
String numeroFactura(String establecimiento, String punto, int numero) =>
    '$establecimiento-$punto ${numero.toString().padLeft(7, '0')}';

/// 2027-08-31 (solo la fecha, sin hora: así no cambia con la zona horaria).
String fechaIsoDia(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
