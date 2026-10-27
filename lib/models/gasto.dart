import 'json.dart';

const categoriasGasto = [
  'Combustible',
  'Flete',
  'Viáticos',
  'Mantenimiento del vehículo',
  'Sueldos y pagos',
  'Teléfono e internet',
  'Alquiler',
  'Impuestos',
  'Útiles y papelería',
  'Otros',
];

class Gasto {
  final String id;
  final DateTime fecha;
  final String categoria;
  final int monto;
  final String? descripcion;
  final String? factura;
  final String? registradoPor;
  final bool anulado;
  final String? motivoAnulacion;

  const Gasto({
    required this.id,
    required this.fecha,
    required this.categoria,
    required this.monto,
    this.descripcion,
    this.factura,
    this.registradoPor,
    this.anulado = false,
    this.motivoAnulacion,
  });

  factory Gasto.fromMap(Map<String, dynamic> m) => Gasto(
        id: m['id'] as String,
        fecha: toDate(m['fecha']),
        categoria: m['categoria'] as String,
        monto: toInt(m['monto']),
        descripcion: textOrNull(m['descripcion']),
        factura: textOrNull(m['factura']),
        registradoPor: m['registrado_por'] as String?,
        anulado: toBool(m['anulado']),
        motivoAnulacion: textOrNull(m['motivo_anulacion']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'fecha': fecha.toIso8601String(),
        'categoria': categoria,
        'monto': monto,
        'descripcion': descripcion,
        'factura': factura,
        'registrado_por': registradoPor,
        'anulado': anulado,
        'motivo_anulacion': motivoAnulacion,
      };
}
