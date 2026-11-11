import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/playlist.dart';
import '../ui/widgets/snackbar.dart';
import 'constant.dart';
import 'music_service.dart';
import 'nav_parser.dart';
import 'ytm_auth_service.dart';

class YtmLibraryService extends GetxService {
  YtmAuthService get _authSvc => Get.find<YtmAuthService>();
  MusicServices get _musicSvc => Get.find<MusicServices>();

  // ── Önbellek Durumu ───────────────────────────────────────────────────────
  List<Playlist> _cachedPlaylists = [];
  DateTime? _playlistsLastFetch;

  Set<String> _cachedLikedSongIds = {};
  DateTime? _likedSongsLastFetch;

  static const Duration _cacheDuration = Duration(minutes: 5);

  final isPlaylistsLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    // Oturum durumu her değiştiğinde (bağlama ve koparma) önbelleği temizle
    ever(_authSvc.isLinked, (_) {
      clearCache();
    });
  }

  void clearCache() {
    _cachedPlaylists = [];
    _playlistsLastFetch = null;
    _cachedLikedSongIds.clear();
    _likedSongsLastFetch = null;
  }

  /// Çalma listeleri önbelleğini geçersiz kılar, sonraki fetchLikedPlaylists taze çeker.
  void invalidatePlaylistsCache() {
    _playlistsLastFetch = null;
  }

  Playlist get likedSongsPlaceholder => Playlist(
        title: 'ytmLikedSongs'.tr,
        playlistId: 'LM',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        description: 'YouTube Music',
        isYtmPlaylist: true,
        isCloudPlaylist: true,
      );

  // ── Çalma Listelerini Çekme (FEmusic_liked_playlists) ─────────────────────

  Future<List<Playlist>> fetchLikedPlaylists({bool forceRefresh = false}) async {
    if (!_authSvc.isLinked.value) return [];

    if (!forceRefresh &&
        _playlistsLastFetch != null &&
        DateTime.now().difference(_playlistsLastFetch!) < _cacheDuration &&
        _cachedPlaylists.isNotEmpty) {
      return _cachedPlaylists;
    }

    isPlaylistsLoading.value = true;
    try {
      const url = '$baseUrl' 'browse$fixedParms';
      final data = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20230213.01.00',
          },
          'user': {},
        },
        'browseId': 'FEmusic_liked_playlists',
      };

      final response = await _musicSvc.dio.post(
        url,
        options: Options(headers: _musicSvc.buildHeaders()),
        data: data,
      );

      final parsed = _parseLikedPlaylists(response.data);

      // Beğenilen Şarkılar ("LM") listesini en başa ekle (eğer listede yoksa)
      final items = <Playlist>[];
      final hasLm = parsed.any((p) => p.playlistId == 'LM' || p.playlistId == 'VLLM');
      if (!hasLm) {
        items.add(likedSongsPlaceholder);
      }
      items.addAll(parsed);

      _cachedPlaylists = items;
      _playlistsLastFetch = DateTime.now();
      return _cachedPlaylists;
    } on DioException catch (e) {
      await _handleAuthError(e.response?.statusCode);
      // Hata durumunda sadece yer tutucu LM döndür
      return [likedSongsPlaceholder];
    } catch (_) {
      return [likedSongsPlaceholder];
    } finally {
      isPlaylistsLoading.value = false;
    }
  }

  List<Playlist> _parseLikedPlaylists(dynamic responseData) {
    final playlists = <Playlist>[];
    if (responseData is! Map) return playlists;

    void extractFromItems(List items) {
      for (final item in items) {
        if (item is! Map) continue;
        final renderer = item['musicTwoRowItemRenderer'] ??
            item['musicResponsiveListItemRenderer'];
        if (renderer is Map) {
          try {
            final pl = parsePlaylist(Map<String, dynamic>.from(renderer));
            if (pl.title.isNotEmpty && pl.playlistId.isNotEmpty) {
              playlists.add(pl.copyWith(isYtmPlaylist: true));
            }
          } catch (_) {}
        }
      }
    }

    final sections = nav(responseData, single_column_tab + section_list);
    if (sections is List) {
      for (final section in sections) {
        if (section is! Map) continue;
        if (section['gridRenderer']?['items'] is List) {
          extractFromItems(section['gridRenderer']['items']);
        } else if (section['musicShelfRenderer']?['contents'] is List) {
          extractFromItems(section['musicShelfRenderer']['contents']);
        } else if (section['itemSectionRenderer']?['contents'] is List) {
          extractFromItems(section['itemSectionRenderer']['contents']);
        }
      }
    }

    if (playlists.isEmpty) {
      void deepSearch(dynamic node) {
        if (node is Map) {
          if (node.containsKey('musicTwoRowItemRenderer') &&
              node['musicTwoRowItemRenderer'] is Map) {
            try {
              final pl = parsePlaylist(
                  Map<String, dynamic>.from(node['musicTwoRowItemRenderer']));
              if (pl.title.isNotEmpty && pl.playlistId.isNotEmpty) {
                playlists.add(pl.copyWith(isYtmPlaylist: true));
              }
            } catch (_) {}
          } else {
            for (final v in node.values) {
              deepSearch(v);
            }
          }
        } else if (node is List) {
          for (final e in node) {
            deepSearch(e);
          }
        }
      }

      deepSearch(responseData);
    }

    return playlists;
  }

  // ── Beğenilen Şarkılar Kimlik Önbelleği (Fallback Kontrolü) ────────────────

  Future<Set<String>> fetchLikedSongIds({bool forceRefresh = false}) async {
    if (!_authSvc.isLinked.value) return {};

    if (!forceRefresh &&
        _likedSongsLastFetch != null &&
        DateTime.now().difference(_likedSongsLastFetch!) < _cacheDuration &&
        _cachedLikedSongIds.isNotEmpty) {
      return _cachedLikedSongIds;
    }

    try {
      final result =
          await _musicSvc.getPlaylistOrAlbumSongs(playlistId: 'LM', limit: 100);
      final tracks = result['tracks'] as List? ?? [];
      final ids = <String>{};
      for (final t in tracks) {
        if (t is MediaItem && t.id.isNotEmpty) {
          ids.add(t.id);
        }
      }
      _cachedLikedSongIds = ids;
      _likedSongsLastFetch = DateTime.now();
      return _cachedLikedSongIds;
    } catch (_) {
      return _cachedLikedSongIds;
    }
  }

  bool isSongInCachedLiked(String songId) {
    return _cachedLikedSongIds.contains(songId);
  }

  // ── Beğen / Beğeniyi Kaldır (like/like, like/removelike) ───────────────────

  /// YouTube Music üzerinde şarkıyı beğenir.
  /// Gövde kuralı: yalnızca {"target": {"videoId": videoId}}
  Future<bool> likeSong(String videoId) async {
    if (!_authSvc.isLinked.value) return false;

    const url = '$baseUrl' 'like/like$fixedParms';
    final data = {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20230213.01.00',
        },
        'user': {},
      },
      'target': {'videoId': videoId},
    };

    try {
      final response = await _musicSvc.dio.post(
        url,
        options: Options(headers: _musicSvc.buildHeaders()),
        data: data,
      );

      if (response.statusCode == 200) {
        _cachedLikedSongIds.add(videoId);
        return true;
      }
      return false;
    } on DioException catch (e) {
      await _handleAuthError(e.response?.statusCode);
      return false;
    } catch (_) {
      _showRequestFailedSnackbar();
      return false;
    }
  }

  /// YouTube Music üzerinde şarkının beğenisini kaldırır.
  /// Gövde kuralı: yalnızca {"target": {"videoId": videoId}}
  Future<bool> unlikeSong(String videoId) async {
    if (!_authSvc.isLinked.value) return false;

    const url = '$baseUrl' 'like/removelike$fixedParms';
    final data = {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20230213.01.00',
        },
        'user': {},
      },
      'target': {'videoId': videoId},
    };

    try {
      final response = await _musicSvc.dio.post(
        url,
        options: Options(headers: _musicSvc.buildHeaders()),
        data: data,
      );

      if (response.statusCode == 200) {
        _cachedLikedSongIds.remove(videoId);
        return true;
      }
      return false;
    } on DioException catch (e) {
      await _handleAuthError(e.response?.statusCode);
      return false;
    } catch (_) {
      _showRequestFailedSnackbar();
      return false;
    }
  }

  // ── Hata Politikası ───────────────────────────────────────────────────────
  // Yalnızca 401'de VEYA 403 + account_menu doğrulaması da başarısızsa çerezi temizle.
  // Tek bir 403'te oturumu kapatma, "YouTube isteği başarısız" göster.

  Future<void> _handleAuthError(int? statusCode) async {
    if (statusCode == 401) {
      await _authSvc.clearCredentials();
      _showSessionExpiredSnackbar();
      return;
    }

    if (statusCode == 403) {
      final stillValid = await _authSvc.verifyCurrentCredentials();
      if (!stillValid) {
        await _authSvc.clearCredentials();
        _showSessionExpiredSnackbar();
        return;
      }
    }

    _showRequestFailedSnackbar();
  }

  void _showSessionExpiredSnackbar() {
    final ctx = Get.context;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        snackbar(ctx, 'ytmSessionExpired'.tr, size: SanckBarSize.BIG),
      );
    }
  }

  void _showRequestFailedSnackbar() {
    final ctx = Get.context;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        snackbar(ctx, 'ytmRequestFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    }
  }
}
