import 'package:latlong2/latlong.dart';

class PolygonLogPreviewData {
  final String polygonKind;
  final String originDocType;
  final String originDocId;
  final int? eventReceivedAtMs;
  final List<LatLng> polygonPoints;
  final LatLng? collarPosition;

  const PolygonLogPreviewData({
    required this.polygonKind,
    required this.originDocType,
    required this.originDocId,
    required this.eventReceivedAtMs,
    required this.polygonPoints,
    required this.collarPosition,
  });
}

class PolygonLogPreviewResolution {
  final PolygonLogPreviewData? data;
  final String? errorMessage;

  const PolygonLogPreviewResolution._({
    required this.data,
    required this.errorMessage,
  });

  const PolygonLogPreviewResolution.success(PolygonLogPreviewData data)
      : this._(data: data, errorMessage: null);

  const PolygonLogPreviewResolution.error(String message)
      : this._(data: null, errorMessage: message);

  bool get ok => data != null;
}

String polygonLogPreviewKindLabel(String polygonKind) {
  switch (polygonKind.trim().toLowerCase()) {
    case 'property':
      return 'Fazenda';
    case 'area':
      return 'Piquete';
    case 'herding':
      return 'Conducao';
    default:
      return 'Poligono';
  }
}

String buildPolygonLogPreviewSvg(PolygonLogPreviewData data) {
  final allPoints = <LatLng>[
    ...data.polygonPoints,
    if (data.collarPosition != null) data.collarPosition!,
  ];
  if (allPoints.isEmpty) {
    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 420 280">
  <rect width="420" height="280" fill="#F6FAF5"/>
  <text x="20" y="40" fill="#244230" font-size="16">Sem dados para renderizar o mapa.</text>
</svg>
''';
  }

  var minLat = allPoints.first.latitude;
  var maxLat = allPoints.first.latitude;
  var minLon = allPoints.first.longitude;
  var maxLon = allPoints.first.longitude;
  for (final point in allPoints.skip(1)) {
    if (point.latitude < minLat) minLat = point.latitude;
    if (point.latitude > maxLat) maxLat = point.latitude;
    if (point.longitude < minLon) minLon = point.longitude;
    if (point.longitude > maxLon) maxLon = point.longitude;
  }

  const width = 420.0;
  const height = 280.0;
  const headerHeight = 48.0;
  const padding = 22.0;
  const usableWidth = width - (padding * 2);
  const usableHeight = height - headerHeight - (padding * 2);

  final lonSpan =
      (maxLon - minLon).abs() < 0.000001 ? 0.000001 : (maxLon - minLon);
  final latSpan =
      (maxLat - minLat).abs() < 0.000001 ? 0.000001 : (maxLat - minLat);

  ({double x, double y}) project(LatLng point) {
    final normalizedX = (point.longitude - minLon) / lonSpan;
    final normalizedY = (maxLat - point.latitude) / latSpan;
    return (
      x: padding + (normalizedX * usableWidth),
      y: headerHeight + padding + (normalizedY * usableHeight),
    );
  }

  final polygonPath = data.polygonPoints
      .map(project)
      .map((point) =>
          '${point.x.toStringAsFixed(1)},${point.y.toStringAsFixed(1)}')
      .join(' ');
  final vertexCircles = data.polygonPoints
      .map(project)
      .map(
        (point) =>
            '<circle cx="${point.x.toStringAsFixed(1)}" cy="${point.y.toStringAsFixed(1)}" r="3.5" fill="#24523A" stroke="#F6FAF5" stroke-width="1.5" />',
      )
      .join();

  final collarPoint =
      data.collarPosition == null ? null : project(data.collarPosition!);
  final collarMarker = collarPoint == null
      ? ''
      : '''
<circle cx="${collarPoint.x.toStringAsFixed(1)}" cy="${collarPoint.y.toStringAsFixed(1)}" r="7" fill="#C65102" fill-opacity="0.2" />
<circle cx="${collarPoint.x.toStringAsFixed(1)}" cy="${collarPoint.y.toStringAsFixed(1)}" r="4.5" fill="#C65102" stroke="#FFFFFF" stroke-width="1.5" />
<line x1="${(collarPoint.x - 8).toStringAsFixed(1)}" y1="${collarPoint.y.toStringAsFixed(1)}" x2="${(collarPoint.x + 8).toStringAsFixed(1)}" y2="${collarPoint.y.toStringAsFixed(1)}" stroke="#8A3800" stroke-width="1.4" />
<line x1="${collarPoint.x.toStringAsFixed(1)}" y1="${(collarPoint.y - 8).toStringAsFixed(1)}" x2="${collarPoint.x.toStringAsFixed(1)}" y2="${(collarPoint.y + 8).toStringAsFixed(1)}" stroke="#8A3800" stroke-width="1.4" />
''';

  final eventTime =
      data.eventReceivedAtMs == null || data.eventReceivedAtMs! <= 0
          ? 'Sem horario'
          : DateTime.fromMillisecondsSinceEpoch(data.eventReceivedAtMs!)
              .toLocal()
              .toString();
  final title = _escapeSvgText(
    '${polygonLogPreviewKindLabel(data.polygonKind)} | ${data.originDocType} | $eventTime',
  );
  final subtitle = _escapeSvgText(
    'Pontos: ${data.polygonPoints.length}${data.collarPosition == null ? ' | Posicao da coleira indisponivel' : ''}',
  );

  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 420 280">
  <rect width="420" height="280" rx="16" fill="#F6FAF5" />
  <rect x="12" y="12" width="396" height="256" rx="14" fill="#FCFEFC" stroke="#B8CFBD" stroke-width="1.5" />
  <rect x="12" y="12" width="396" height="44" rx="14" fill="#E3EFE5" />
  <text x="24" y="31" fill="#193324" font-size="14" font-family="sans-serif" font-weight="700">$title</text>
  <text x="24" y="47" fill="#4B6A58" font-size="11" font-family="sans-serif">$subtitle</text>
  <polygon points="$polygonPath" fill="#3B7A57" fill-opacity="0.18" stroke="#24523A" stroke-width="3" stroke-linejoin="round" />
  $vertexCircles
  $collarMarker
</svg>
''';
}

String _escapeSvgText(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
