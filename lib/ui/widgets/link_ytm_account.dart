import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../utils/helper.dart';
import '/services/music_service.dart';
import '/services/ytm_auth_service.dart';
import '../screens/Settings/settings_screen_controller.dart';
import 'common_dialog_widget.dart';
import 'modified_text_field.dart';
import 'snackbar.dart';

// ── Controller ───────────────────────────────────────────────────────────────

class LinkYtmController extends GetxController {
  final cookieController = TextEditingController();
  final errorText = ''.obs;
  final loading = false.obs;
  final howToVisible = false.obs;

  @override
  void onClose() {
    cookieController.dispose();
    super.onClose();
  }

  Future<void> connect() async {
    final cookie = cookieController.text.trim();
    final authSvc = Get.find<YtmAuthService>();

    // 1. Format kontrolü
    if (!authSvc.validateCookieFormat(cookie)) {
      errorText.value = 'ytmInvalidCookie'.tr;
      return;
    }

    errorText.value = '';
    loading.value = true;

    try {
      // 2. Hesap adını doğrula
      final name = await _fetchAccountName(cookie);

      // 3. Kaydet
      await authSvc.saveCredentials(cookie: cookie, name: name);

      Get.find<SettingsScreenController>().ytmLinkLoading.value = false;
      Navigator.of(Get.context!).pop();

      ScaffoldMessenger.of(Get.context!).showSnackBar(
        snackbar(Get.context!, 'ytmConnectSuccess'.tr,
            size: SanckBarSize.MEDIUM),
      );
    } on _AuthException catch (e) {
      // Cookie geçerli format fakat sunucu 401/403 döndü
      errorText.value = e.message;
    } catch (e) {
      // Ağ hatası vb. — değeri loglama
      errorText.value = 'networkError1'.tr;
      printINFO('YTM doğrulama hatası: [gizli]');
    } finally {
      loading.value = false;
    }
  }

  /// account/account_menu browse isteği.
  /// ytmusicapi referansına göre giriş yapmış kullanıcıda hesap adı buradan gelir.
  Future<String> _fetchAccountName(String cookie) async {
    final authSvc = Get.find<YtmAuthService>();
    final musicSvc = Get.find<MusicServices>();

    final authHeader = authSvc.buildAuthHeader(cookie);

    final headers = {
      'accept': '*/*',
      'content-type': 'application/json',
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
      'origin': 'https://music.youtube.com',
      'x-origin': 'https://music.youtube.com',
      'Cookie': cookie,
      if (authHeader.isNotEmpty) 'Authorization': authHeader,
      'X-Goog-AuthUser': '0',
    };

    const url =
        'https://music.youtube.com/youtubei/v1/account/account_menu?prettyPrint=false&alt=json&key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

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
      // actions > openPopupAction > popup > multiPageMenuRenderer > header >
      // activeAccountHeaderRenderer > accountName > runs[0] > text
      final actions = data['actions'] as List?;
      if (actions != null && actions.isNotEmpty) {
        final popup =
            actions[0]?['openPopupAction']?['popup'];
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

    // Yanıt yapısı farklıysa giriş başarılı ama ad çıkarılamadı
    return 'YouTube';
  }
}

class _AuthException implements Exception {
  _AuthException(this.message);
  final String message;
}

// ── Widget ───────────────────────────────────────────────────────────────────

class LinkYtmAccount extends StatelessWidget {
  const LinkYtmAccount({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(LinkYtmController());
    return CommonDialog(
      child: Obx(
        () => Container(
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
                controller: ctrl.cookieController,
                decoration: InputDecoration(
                  hintText: 'ytmPasteHint'.tr,
                  labelText: 'ytmPasteLabel'.tr,
                ),
                onChanged: (_) {
                  if (ctrl.errorText.value.isNotEmpty) {
                    ctrl.errorText.value = '';
                  }
                },
              ),

              // Hata mesajı
              if (ctrl.errorText.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    ctrl.errorText.value,
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
                    ctrl.howToVisible.value = !ctrl.howToVisible.value,
                child: Row(
                  children: [
                    Icon(
                      ctrl.howToVisible.isTrue
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
              if (ctrl.howToVisible.isTrue)
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
                    onPressed: ctrl.loading.isTrue
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text('cancel'.tr),
                  ),
                  const SizedBox(width: 8),
                  ctrl.loading.isTrue
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ElevatedButton(
                          onPressed: ctrl.connect,
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
