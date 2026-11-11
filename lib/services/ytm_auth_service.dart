// ignore_for_file: constant_identifier_names

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Hive box adı — AppPrefs'ten kasıtlı olarak ayrı tutulur.
/// Bu box yedekleme ve dışa aktarma işlemlerinden HARİÇ tutulur.
/// main.dart/initHive() tarafından uygulama başlarken açılır;
/// servis bu box'a her zaman Hive.box() ile senkron erişir (openBox yok).
const _kBoxName = 'ytmAuth';

/// AppPrefs veya herhangi bir log'a cookie değeri yazılmaz.
/// Hash üretiminde SAPISID yoksa __Secure-3PAPISID kullanılır.
class YtmAuthService extends GetxService {
  /// Reactive durum — UI bu değerleri izler.
  final isLinked = false.obs;
  final accountName = ''.obs;

  /// Box'a senkron erişim — main.dart garantili açmış olmalı.
  /// Box kapalıysa null döner; çağıranlar bunu kontrol eder.
  Box? get _box {
    if (Hive.isBoxOpen(_kBoxName)) return Hive.box(_kBoxName);
    return null;
  }

  @override
  void onInit() {
    _restoreState();
    super.onInit();
  }

  // ── Dahili yardımcılar ────────────────────────────────────────────────────

  void _restoreState() {
    final box = _box;
    if (box == null) return;
    final stored = box.get('cookie');
    isLinked.value = stored != null && stored.toString().isNotEmpty;
    accountName.value = box.get('accountName') ?? '';
  }

  /// Cookie metninden SAPISID veya __Secure-3PAPISID değerini çıkarır.
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

  /// Depolanmış cookie değerini döndürür; box kapalıysa veya kayıt yoksa null.
  String? get storedCookie {
    final v = _box?.get('cookie');
    return (v != null && v.toString().isNotEmpty) ? v.toString() : null;
  }

  /// Cookie değerinin SAPISID içerip içermediğini kontrol eder.
  bool validateCookieFormat(String cookie) {
    return _extractSapisid(cookie) != null;
  }

  /// Cookie'yi saklar, hesap adını Hive'a yazar, reactive durumu günceller.
  Future<void> saveCredentials({
    required String cookie,
    required String name,
  }) async {
    // Cookie ham string olarak saklanır — log satırı yok.
    final box = _box;
    if (box == null) return;
    await box.put('cookie', cookie);
    await box.put('accountName', name);
    isLinked.value = true;
    accountName.value = name;
  }

  /// Oturumu kapatır, Hive'daki verileri siler.
  Future<void> clearCredentials() async {
    final box = _box;
    if (box == null) return;
    await box.delete('cookie');
    await box.delete('accountName');
    isLinked.value = false;
    accountName.value = '';
  }

  /// Mevcut çerezin hâlâ geçerli olup olmadığını account_menu çağrısıyla doğrular.
  /// 200 dönerse true, 401/403 veya ağ hatasında false döner.
  Future<bool> verifyCurrentCredentials() async {
    final cookie = storedCookie;
    if (cookie == null) return false;
    try {
      final authHeader = buildAuthHeader(cookie);
      final headers = {
        'accept': '*/*',
        'content-type': 'application/json',
        'origin': 'https://music.youtube.com',
        'x-origin': 'https://music.youtube.com',
        'Cookie': cookie,
        if (authHeader.isNotEmpty) 'Authorization': authHeader,
        'X-Goog-AuthUser': '0',
      };
      const url =
          'https://music.youtube.com/youtubei/v1/account/account_menu?prettyPrint=false&alt=json&key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
      final dio = Dio();
      final response = await dio.post(
        url,
        options: Options(headers: headers),
        data: {
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20230213.01.00'
            },
            'user': {},
          },
        },
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // onClose'da box'u kapatmıyoruz — main.dart/Hive.close() halleder.
}
