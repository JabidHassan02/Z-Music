import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DownloadAccessKeyStore {
  static const int requiredLength = 50;
  static const String _storageKey = 'rapidapi_access_key';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> read() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.length != requiredLength) return null;
    return trimmed;
  }

  static Future<void> save(String value) async {
    final trimmed = value.trim();
    if (trimmed.length != requiredLength) {
      throw const FormatException('Access key must be exactly 50 characters.');
    }
    await _storage.write(key: _storageKey, value: trimmed);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _storageKey);
  }
}
