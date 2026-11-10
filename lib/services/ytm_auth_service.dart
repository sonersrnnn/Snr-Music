// ignore_for_file: constant_identifier_names

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Hive box adı — AppPrefs'ten kasıtlı olarak ayrı tutulur.
/// Bu box yedekleme ve dışa aktarma işlemlerinden HARİÇ tutulur.
const _kBoxName = 'ytmAuth';

/// AppPrefs veya herhangi bir log'a cookie değeri yazılmaz.
/// Hash üretiminde SAPISID yoksa __Secure-3PAPISID kullanılır.
class YtmAuthService extends GetxService {
  late Box _box;

  /// Reactive durum — UI bu değerleri izler.
  final isLinked = false.obs;
  final accountName = ''.obs;

  @override
  Future<void> onInit() async {
    _box = await Hive.openBox(_kBoxName);
    _restoreState();
    super.onInit();
  }

  // ── Dahili yardımcılar ────────────────────────────────────────────────────

  void _restoreState() {
    final stored = _box.get('cookie');
    isLinked.value = stored != null && stored.toString().isNotEmpty;
    accountName.value = _box.get('accountName') ?? '';
  }

  /// Cookie metninden SAPISID veya __Secure-3PAPISID değerini çıkarır.
  /// Bulunan değeri döndürür; bulunamazsa null döner.
  String? _extractSapisid(String cookie) {
    for (final key in ['SAPISID', '__Secure-3PAPISID']) {
      final pattern = RegExp('(?:^|;)\\s*${RegExp.escape(key)}=([^;]+)');
      final match = pattern.firstMatch(cookie);
      if (match != null) return match.group(1)?.trim();
    }
    return null;
  }

  /// RFC: SAPISIDHASH <ts>_<sha1("<ts> <sapisid> https://music.youtube.com")>
  /// Her istekte çağrılır — ts her seferinde yeniden üretilir.
  String buildAuthHeader(String cookie) {
    final sapisid = _extractSapisid(cookie);
    if (sapisid == null) return '';
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = '$ts $sapisid https://music.youtube.com';
    final digest = sha1.convert(utf8.encode(payload));
    return 'SAPISIDHASH ${ts}_$digest';
  }

  // ── Genel API ─────────────────────────────────────────────────────────────

  /// Depolanmış cookie değerini döndürür; yoksa null.
  String? get storedCookie {
    final v = _box.get('cookie');
    return (v != null && v.toString().isNotEmpty) ? v.toString() : null;
  }

  /// Cookie değerinin SAPISID içerip içermediğini kontrol eder.
  bool validateCookieFormat(String cookie) {
    return _extractSapisid(cookie) != null;
  }

  /// Cookie'yi saklar, hesap adını Hive'a yazar, reactive durumu günceller.
  /// Dışarıdan sadece [AccountVerifier] çağırır.
  Future<void> saveCredentials({
    required String cookie,
    required String name,
  }) async {
    // Cookie ham string olarak saklanır — log satırı yok.
    await _box.put('cookie', cookie);
    await _box.put('accountName', name);
    isLinked.value = true;
    accountName.value = name;
  }

  /// Oturumu kapatır, Hive'daki verileri siler.
  Future<void> clearCredentials() async {
    await _box.delete('cookie');
    await _box.delete('accountName');
    isLinked.value = false;
    accountName.value = '';
  }

  @override
  Future<void> onClose() async {
    await _box.close();
    super.onClose();
  }
}
