import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../utils/helper.dart';
import '/services/music_service.dart';
import '/services/ytm_auth_service.dart';
import 'common_dialog_widget.dart';
import 'modified_text_field.dart';
import 'snackbar.dart';

// ── Saf veri sınıfı (GetxController değil) ───────────────────────────────────

class _YtmLinkState {
  final cookieCtrl = TextEditingController();
  String errorText = '';
  bool loading = false;
  bool howToVisible = false;
}

class _AuthException implements Exception {
  _AuthException(this.message);
  final String message;
}

// ── Hesap adı çekme (bağımsız fonksiyon) ─────────────────────────────────────

/// account/account_menu browse isteği.
/// Cookie ham değeri sadece istek başlığına gider, hiçbir yere loglanmaz.
Future<String> _fetchAccountName(String cookie) async {
  final authSvc = Get.find<YtmAuthService>();
  final musicSvc = Get.find<MusicServices>();
  final authHeader = authSvc.buildAuthHeader(cookie);

  final headers = {
    'accept': '*/*',
    'content-type': 'application/json',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
    'origin': 'https://music.youtube.com',
    'x-origin': 'https://music.youtube.com',
    'Cookie': cookie,
    if (authHeader.isNotEmpty) 'Authorization': authHeader,
    'X-Goog-AuthUser': '0',
  };

  const url = 'https://music.youtube.com/youtubei/v1/account/account_menu'
      '?prettyPrint=false&alt=json&key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

  final body = {
    'context': {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20230213.01.00',
      },
      'user': {},
    },
  };

  dio_pkg.Response response;
  try {
    response = await musicSvc.dio.post(
      url,
      options: dio_pkg.Options(headers: headers),
      data: body,
    );
  } on dio_pkg.DioException catch (e) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) throw _AuthException('ytmAuthFailed'.tr);
    rethrow;
  }

  if (response.statusCode == 401 || response.statusCode == 403) {
    throw _AuthException('ytmAuthFailed'.tr);
  }

  // Hesap adını yanıttan çıkar
  try {
    final data = response.data;
    final actions = data['actions'] as List?;
    if (actions != null && actions.isNotEmpty) {
      final popup = actions[0]?['openPopupAction']?['popup'];
      final header = popup?['multiPageMenuRenderer']?['header']
          ?['activeAccountHeaderRenderer'];
      if (header != null) {
        final runs = header['accountName']?['runs'] as List?;
        if (runs != null && runs.isNotEmpty) {
          final name = runs[0]['text']?.toString() ?? '';
          if (name.isNotEmpty) return name;
        }
      }
    }
  } catch (_) {}

  return 'YouTube';
}

// ── Widget (StatefulWidget — hiç GetxController yok) ─────────────────────────

class LinkYtmAccount extends StatefulWidget {
  const LinkYtmAccount({super.key});

  @override
  State<LinkYtmAccount> createState() => _LinkYtmAccountState();
}

class _LinkYtmAccountState extends State<LinkYtmAccount> {
  final _state = _YtmLinkState();

  @override
  void dispose() {
    _state.cookieCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final cookie = _state.cookieCtrl.text.trim();
    final authSvc = Get.find<YtmAuthService>();

    // 1. Format kontrolü
    if (!authSvc.validateCookieFormat(cookie)) {
      setState(() => _state.errorText = 'ytmInvalidCookie'.tr);
      return;
    }

    setState(() {
      _state.errorText = '';
      _state.loading = true;
    });

    try {
      // 2. Hesap adını doğrula
      final name = await _fetchAccountName(cookie);

      // 3. Dialogo ÖNCE kapat, SONRA kaydet — build scope hatalarından kaçın
      if (!mounted) return;
      Navigator.of(context).pop();

      // 4. Pop tamamlandıktan sonraki frame'de kaydet + snackbar
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await authSvc.saveCredentials(cookie: cookie, name: name);
        final ctx = Get.context;
        if (ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            snackbar(ctx, 'ytmConnectSuccess'.tr, size: SanckBarSize.MEDIUM),
          );
        }
      });
    } on _AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _state.errorText = e.message;
        _state.loading = false;
      });
    } catch (_) {
      // Ağ hatası vb. — değeri loglama
      printINFO('YTM doğrulama hatası: [gizli]');
      if (!mounted) return;
      setState(() {
        _state.errorText = 'networkError1'.tr;
        _state.loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık
              Text(
                'ytmAccount'.tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              // Yapıştırma kutusu
              ModifiedTextField(
                controller: _state.cookieCtrl,
                decoration: InputDecoration(
                  hintText: 'ytmPasteHint'.tr,
                  labelText: 'ytmPasteLabel'.tr,
                ),
                onChanged: (_) {
                  if (_state.errorText.isNotEmpty) {
                    setState(() => _state.errorText = '');
                  }
                },
              ),

              // Hata mesajı
              if (_state.errorText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _state.errorText,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall!
                        .copyWith(color: Colors.redAccent),
                  ),
                ),

              const SizedBox(height: 8),

              // "Nasıl alınır?" açılır yardım
              InkWell(
                onTap: () =>
                    setState(() => _state.howToVisible = !_state.howToVisible),
                child: Row(
                  children: [
                    Icon(
                      _state.howToVisible
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'ytmHowToTitle'.tr,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_state.howToVisible)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'ytmHowTo'.tr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),

              const SizedBox(height: 20),

              // Butonlar
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _state.loading ? null : () => Navigator.of(context).pop(),
                    child: Text('cancel'.tr),
                  ),
                  const SizedBox(width: 8),
                  _state.loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ElevatedButton(
                          onPressed: _connect,
                          child: Text('ytmLink'.tr),
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
