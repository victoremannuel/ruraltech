class FirebaseException implements Exception {
  FirebaseException({
    required this.plugin,
    required this.code,
    this.message,
  });

  final String plugin;
  final String code;
  final String? message;

  @override
  String toString() => message == null || message!.trim().isEmpty
      ? '$plugin/$code'
      : '$plugin/$code: $message';
}

class FirebaseAuthException extends FirebaseException {
  FirebaseAuthException({
    required super.code,
    super.message,
  }) : super(plugin: 'firebase_auth');
}

class DocumentReference<T> {
  const DocumentReference({
    required this.id,
    required this.path,
  });

  final String id;
  final String path;
}

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class Timestamp {
  const Timestamp._(this._dateTime);

  final DateTime _dateTime;

  factory Timestamp.fromDate(DateTime value) => Timestamp._(value.toUtc());

  factory Timestamp.fromMillisecondsSinceEpoch(int millisecondsSinceEpoch) =>
      Timestamp._(
        DateTime.fromMillisecondsSinceEpoch(
          millisecondsSinceEpoch,
          isUtc: true,
        ),
      );

  DateTime toDate() => _dateTime.toLocal();

  int get millisecondsSinceEpoch => _dateTime.millisecondsSinceEpoch;
}
