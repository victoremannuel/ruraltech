String? resolveHomeAuthKey({
  required String? uid,
  required String role,
}) {
  final normalizedUid = uid?.trim() ?? '';
  if (normalizedUid.isEmpty) return null;
  return '$normalizedUid-${role.trim().toLowerCase()}';
}

bool shouldShowBlockingHomeLoader({
  required String? uid,
  required bool isProfileLoading,
  required String? lastReadyAuthKey,
}) {
  if ((uid?.trim() ?? '').isEmpty) return true;
  return isProfileLoading && lastReadyAuthKey == null;
}

List<String> collectHomeLoadIssues({
  Object? propertiesError,
  Object? areasError,
  Object? devicesError,
  Object? gatewaysError,
  String? adminBootstrapError,
}) {
  final issues = <String>[];
  if (propertiesError != null) {
    issues.add('Falha ao carregar propriedades.');
  }
  if (areasError != null) {
    issues.add('Falha ao carregar areas.');
  }
  if (devicesError != null) {
    issues.add('Falha ao carregar coleiras.');
  }
  if (gatewaysError != null) {
    issues.add('Falha ao carregar gateways.');
  }
  final normalizedAdminError = adminBootstrapError?.trim() ?? '';
  if (normalizedAdminError.isNotEmpty) {
    issues.add(normalizedAdminError);
  }
  return issues;
}
