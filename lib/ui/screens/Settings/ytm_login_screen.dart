import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import '/services/ytm_auth_service.dart';
import '/ui/widgets/link_ytm_account.dart';
import '/ui/widgets/snackbar.dart';

/// Android ve desteklenen mobil platformlar için YouTube Music oturum açma sayfası.
/// `InAppWebViewSettings.incognito: true` ile açılır ve işlem tamamlandığında/iptal edildiğinde
/// çerezleri ve yerel depolamayı temizler.
class YtmLoginScreen extends StatefulWidget {
  const YtmLoginScreen({super.key});

  @override
  State<YtmLoginScreen> createState() => _YtmLoginScreenState();
}

class _YtmLoginScreenState extends State<YtmLoginScreen> {
  bool _isLoading = true;
  bool _isFinalizing = false;

  final CookieManager _cookieManager = CookieManager.instance();

  static const String _initialUrl =
      'https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com';

  @override
  void dispose() {
    _cleanupSession();
    super.dispose();
  }

  /// Oturum verilerini ve WebView çerezlerini temizler.
  Future<void> _cleanupSession() async {
    try {
      await _cookieManager.deleteAllCookies();
      await InAppWebViewController.clearAllCache();
    } catch (_) {}
  }

  /// WebView'da açılan sayfada çerezleri okur ve SAPISID kontrolü yapar.
  Future<void> _checkCookiesAndAuthorize(WebUri? url) async {
    if (_isFinalizing) return;
    if (url == null) return;

    final host = url.host.toLowerCase();
    // Yalnızca music.youtube.com alan adında arama yap
    if (!host.contains('music.youtube.com')) return;

    try {
      final cookies = await _cookieManager.getCookies(url: url);
      if (cookies.isEmpty) return;

      // Çerez listesinden Cookie başlığı metnini oluştur
      final cookieString =
          cookies.map((c) => '${c.name}=${c.value}').join('; ');

      final authSvc = Get.find<YtmAuthService>();
      if (!authSvc.validateCookieFormat(cookieString)) {
        return;
      }

      // Geçerli SAPISID bulundu, bağlama sürecini tamamla
      setState(() {
        _isFinalizing = true;
        _isLoading = true;
      });

      final name = await fetchYtmAccountName(cookieString);

      if (!mounted) return;

      // Ekranı kapat
      Navigator.of(context).pop(true);

      // Pop tamamlandıktan sonra credential'ları kaydet ve snackbar göster
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await authSvc.saveCredentials(cookie: cookieString, name: name);
        final ctx = Get.context;
        if (ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            snackbar(ctx, 'ytmConnectSuccess'.tr, size: SanckBarSize.MEDIUM),
          );
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isFinalizing = false;
          _isLoading = false;
        });
      }
    }
  }

  void _openManualPasteFallback() {
    Navigator.of(context).pop(false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = Get.context;
      if (ctx != null && ctx.mounted) {
        showDialog(
          context: ctx,
          builder: (_) => const LinkYtmAccount(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ytmLoginTitle'.tr,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        actions: [
          TextButton(
            onPressed: _openManualPasteFallback,
            child: Text(
              'ytmPasteLabel'.tr,
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(_initialUrl),
            ),
            initialSettings: InAppWebViewSettings(
              incognito: true,
              javaScriptEnabled: true,
              domStorageEnabled: true,
              thirdPartyCookiesEnabled: true,
              supportZoom: true,
              transparentBackground: false,
              useShouldOverrideUrlLoading: true,
            ),
            onWebViewCreated: (controller) {},
            onLoadStart: (controller, url) {
              if (mounted) setState(() => _isLoading = true);
            },
            onLoadStop: (controller, url) async {
              if (mounted) setState(() => _isLoading = false);
              await _checkCookiesAndAuthorize(url);
            },
            onReceivedError: (controller, request, error) {
              if (mounted) setState(() => _isLoading = false);
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri == null) return NavigationActionPolicy.ALLOW;

              final scheme = uri.scheme.toLowerCase();
              if (scheme == 'http' || scheme == 'https') {
                return NavigationActionPolicy.ALLOW;
              }

              // Intent ve diğer harici şemaların WebView içinde hata vermesini engelle
              return NavigationActionPolicy.CANCEL;
            },
          ),
          if (_isLoading || _isFinalizing)
            Container(
              color: Colors.black38,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _isFinalizing
                          ? 'ytmConnecting'.tr
                          : 'loading'.tr,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
