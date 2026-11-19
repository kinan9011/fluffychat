// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:ui' show Color;

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:managed_configurations/managed_configurations.dart';
import 'package:matrix/matrix.dart' show ShareKeysWith;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:odango/utils/appearance/chat_appearance.dart';
import 'package:odango/utils/branding/repo_links.dart';
import 'package:odango/utils/branding/support_links.dart';
import 'package:odango/utils/oklch.dart';
import 'package:odango/utils/platform_infos.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultColorSchemeSeed = 0xFF5625BA;

enum AppSettings<T> {
  textMessageMaxLength<int>('textMessageMaxLength', 16384),

  /// Max lines for unselected HTML/text bubbles; 0 = unlimited (no fade).
  messagePreviewMaxLines<int>('com.swovo.odango.message_preview_max_lines', 50),
  audioRecordingNumChannels<int>('audioRecordingNumChannels', 1),
  audioRecordingAutoGain<bool>('audioRecordingAutoGain', true),
  audioRecordingEchoCancel<bool>('audioRecordingEchoCancel', false),
  audioRecordingNoiseSuppress<bool>('audioRecordingNoiseSuppress', true),
  audioRecordingBitRate<int>('audioRecordingBitRate', 64000),
  audioRecordingSamplingRate<int>('audioRecordingSamplingRate', 48000),
  showNoGoogle<bool>('com.swovo.odango.show_no_google', false),
  unifiedPushRegistered<bool>('com.swovo.odango.unifiedpush.registered', false),
  unifiedPushEndpoint<String>('com.swovo.odango.unifiedpush.endpoint', ''),
  pushNotificationsGatewayUrl<String>('pushNotificationsGatewayUrl', ''),
  pushNotificationsPusherFormat<String>(
    'pushNotificationsPusherFormat',
    'event_id_only',
  ),
  renderHtml<bool>('com.swovo.odango.renderHtml', true),
  fontSizeFactor<double>('com.swovo.odango.font_size_factor', 1.0),
  hideRedactedEvents<bool>('com.swovo.odango.hideRedactedEvents', false),
  hideUnknownEvents<bool>('com.swovo.odango.hideUnknownEvents', true),
  autoplayImages<bool>('com.swovo.odango.autoplay_images', true),
  sendTypingNotifications<bool>(
    'com.swovo.odango.send_typing_notifications',
    false,
  ),
  sendPublicReadReceipts<bool>(
    'com.swovo.odango.send_public_read_receipts',
    false,
  ),
  shareOnlineStatus<bool>('com.swovo.odango.share_online_status', false),
  appearOffline<bool>('com.swovo.odango.appear_offline', false),
  presenceAway<bool>('com.swovo.odango.presence_away', false),
  defaultDisappearSeconds<int>('com.swovo.odango.default_disappear_seconds', 0),
  swipeRightToLeftToReply<bool>(
    'com.swovo.odango.swipeRightToLeftToReply',
    true,
  ),
  sendOnEnter<bool>('com.swovo.odango.send_on_enter', false),
  shareKeysWith<String>('com.swovo.odango.share_keys_with_2', 'all'),
  noEncryptionWarningShown<bool>(
    'com.swovo.odango.no_encryption_warning_shown',
    false,
  ),
  databaseUnencryptedClients<List<String>>(
    'com.swovo.odango.database_unencrypted_clients',
    [],
  ),
  databaseQuarantinedClients<List<String>>(
    'com.swovo.odango.database_quarantined_clients',
    [],
  ),
  databaseUnencryptedNoticeDismissed<bool>(
    'com.swovo.odango.database_unencrypted_notice_dismissed',
    false,
  ),
  displayChatDetailsColumn(
    'com.swovo.odango.display_chat_details_column',
    false,
  ),
  // AppConfig-mirrored settings
  applicationName<String>('com.swovo.odango.application_name', 'Odango'),
  defaultHomeserver<String>(
    'com.swovo.odango.default_homeserver',
    'matrix.org',
  ),
  // colorSchemeSeed stored as ARGB int
  colorSchemeSeedInt<int>(
    'com.swovo.odango.color_scheme_seed',
    defaultColorSchemeSeed,
  ),
  accentHue<int>('com.swovo.odango.accent_hue', 268),
  reduceTransparency<bool>('com.swovo.odango.reduce_transparency', false),
  glassMode<String>('com.swovo.odango.glass_mode', 'auto'),
  chatWallpaperPreset<String>(
    'com.swovo.odango.chat_wallpaper_preset',
    'default',
  ),
  chatWallpaperLocal<bool>('com.swovo.odango.chat_wallpaper_local', false),
  bubbleCorners<String>('com.swovo.odango.bubble_corners', 'standard'),
  callsEnabled<bool>('com.swovo.odango.calls_enabled', true),
  emojiSuggestionLocale<String>('emoji_suggestion_locale', ''),
  enableSoftLogout<bool>('com.swovo.odango.enable_soft_logout', true),
  enableMatrixNativeOIDC<bool>(
    'com.swovo.odango.enable_matrix_native_oidc',
    true,
  ),
  presetHomeserver<String>('com.swovo.odango.preset_homeserver', ''),
  welcomeText<String>('com.swovo.odango.welcome_text', ''),
  website<String>('com.swovo.odango.website_url', 'https://odango.swovo.de'),
  logoUrl<String>(
    'com.swovo.odango.logo_url',
    'https://odango.swovo.de/assets/favicon.png',
  ),
  privacyPolicy<String>(
    'com.swovo.odango.privacy_policy_url',
    'https://odango.swovo.de/privacy',
  ),
  tos<String>('com.swovo.odango.tos_url', 'https://odango.swovo.de/tos'),
  repositoryUrl<String>(
    'com.swovo.odango.repository_url',
    'https://github.com/kinan9011/odango',
  ),
  repositoryConfirmed<bool>('com.swovo.odango.repository_confirmed', true),
  koFiUrl<String>('com.swovo.odango.ko_fi_url', ''),
  buyMeACoffeeUrl<String>('com.swovo.odango.buy_me_a_coffee_url', ''),
  sendTimelineEventTimeout<int>(
    'com.swovo.odango.send_timeline_event_timeout',
    15,
  ),
  webNotificationSound<bool>('com.swovo.odango.web_notification_sound', true),
  chatFilter<String>('com.swovo.odango.chat_filter', 'allChats'),
  hideRoomsInSpaces<bool>('com.swovo.odango.hideRoomsInSpaces', false),
  spaceNavigation<String>('com.swovo.odango.space_navigation', 'tabs'),
  showFoldersAfterSpaces<bool>(
    'com.swovo.odango.show_folders_after_spaces',
    true,
  ),
  showTabUnreadCounts<bool>('com.swovo.odango.show_tab_unread_counts', true),
  unarchiveOnMention<bool>('com.swovo.odango.unarchive_on_mention', false),
  showThumbnailsInTimeline<bool>(
    'com.swovo.odango.showThumbnailsInTimeline',
    true,
  ),
  doubleTapToReact<bool>('com.swovo.odango.double_tap_to_react', false),
  doubleTapReaction<String>('com.swovo.odango.double_tap_reaction', '❤️'),
  benchmarksInLogs<bool>('com.swovo.odango.benchmarks_in_logs', false),
  autoSendErrorReports<bool?>('com.swovo.odango.auto_send_eror_reports', null),
  knownErrorHashes<List<String>>('com.swovo.odango.known_crash_hashes', []),
  checkForUpdates<bool>('com.swovo.odango.check_for_updates', true),
  lastUpdateCheckDate<String>('com.swovo.odango.last_update_check_date', ''),
  fallbackLiveKitInstance<String>(
    'com.swovo.odango.fallback_live_kit_instance',
    '',
  );

  final String key;
  final T _defaultValue;

  const AppSettings(this.key, this._defaultValue);

  static SharedPreferences get store => _store!;
  static SharedPreferences? _store;

  static final _revisions = <AppSettings<Object?>, ValueNotifier<int>>{};

  ValueListenable<int> get listenable =>
      _revisions.putIfAbsent(this, () => ValueNotifier(0));

  void _notifyChanged() => _revisions[this]?.value++;

  void notifyRemoved() => _notifyChanged();

  static Map<String, Object?>? _platformConfiguration;

  bool get hasPlatformValue => _platformConfiguration?[name] is T;

  static const legacyPrimaryColorKey = 'primary_color';

  T get defaultValue {
    final platformConfig = _platformConfiguration?[name];
    if (platformConfig is T) return platformConfig;
    return _defaultValue;
  }

  static void applyPlatformConfiguration(
    Map<String, Object?>? config,
    PlatformConfigSource source,
  ) => _platformConfiguration = config == null
      ? null
      : filterPlatformConfiguration(config, source);

  static Future<void> reset({bool loadWebConfigFile = true}) async {
    for (final setting in AppSettings.values) {
      await AppSettings.store.remove(setting.key);
    }
    await init(loadWebConfigFile: loadWebConfigFile);
    for (final setting in AppSettings.values) {
      setting._notifyChanged();
    }
  }

  @visibleForTesting
  static Future<void> migrateLegacyAccent(SharedPreferences store) async {
    final legacy = [legacyPrimaryColorKey, colorSchemeSeedInt.key]
        .map((key) => Result(() => store.getInt(key)).asValue?.value)
        .nonNulls
        .firstOrNull;
    if (legacy != null && !store.containsKey(accentHue.key)) {
      final hue = accentHueOf(Color(legacy));
      if (hue != null) await store.setInt(accentHue.key, hue.toInt());
    }
    await store.remove(legacyPrimaryColorKey);
    await store.remove(colorSchemeSeedInt.key);
  }

  static Future<SharedPreferences> init({bool loadWebConfigFile = true}) async {
    if (AppSettings._store != null) return AppSettings.store;

    final store = AppSettings._store = await SharedPreferences.getInstance();

    // Migrate wrong datatype for fontSizeFactor
    final fontSizeFactorString = Result(
      () => store.getString(AppSettings.fontSizeFactor.key),
    ).asValue?.value;
    if (fontSizeFactorString != null) {
      Logs().i('Migrate wrong datatype for fontSizeFactor!');
      await store.remove(AppSettings.fontSizeFactor.key);
      final fontSizeFactor = double.tryParse(fontSizeFactorString);
      if (fontSizeFactor != null) {
        await store.setDouble(AppSettings.fontSizeFactor.key, fontSizeFactor);
      }
    }

    if (store.getBool(AppSettings.sendOnEnter.key) == null) {
      await store.setBool(AppSettings.sendOnEnter.key, !PlatformInfos.isMobile);
    }
    if (store.getBool(AppSettings.doubleTapToReact.key) == null) {
      await store.setBool(
        AppSettings.doubleTapToReact.key,
        PlatformInfos.isMobile,
      );
    }
    await store.remove('com.swovo.odango.database_unencrypted');
    await migrateLegacyAccent(store);

    // Load configuration from config.json file or MDM:
    if (PlatformInfos.isMobile) {
      applyPlatformConfiguration(
        await ManagedConfigurations().getManagedConfigurations,
        PlatformConfigSource.mdm,
      );
    } else if (kIsWeb && loadWebConfigFile) {
      try {
        final configJsonString = utf8.decode(
          (await http.get(Uri.parse('config.json'))).bodyBytes,
        );
        applyPlatformConfiguration(
          json.decode(configJsonString) as Map<String, Object?>,
          PlatformConfigSource.web,
        );
      } on FormatException catch (_) {
        Logs().v('[ConfigLoader] config.json not found');
      } catch (e) {
        Logs().v('[ConfigLoader] config.json not found', e);
      }
    }

    return store;
  }
}

enum PlatformConfigSource {
  /// config.json served next to the web app. Not authenticated and often
  /// cached or edited separately from the app, so only an allowlist applies.
  web,

  mdm,
}

const runtimeStateSettings = <AppSettings<Object?>>{
  AppSettings.showNoGoogle,
  AppSettings.unifiedPushRegistered,
  AppSettings.unifiedPushEndpoint,
  AppSettings.noEncryptionWarningShown,
  AppSettings.databaseUnencryptedClients,
  AppSettings.databaseUnencryptedNoticeDismissed,
  AppSettings.databaseQuarantinedClients,
  AppSettings.knownErrorHashes,
  AppSettings.lastUpdateCheckDate,
};

/// Can redirect data to a third party or weaken the message flow, so a
/// config.json must not change them. Still configurable via MDM.
const webDeniedSettings = <AppSettings<Object?>>{
  ...runtimeStateSettings,
  AppSettings.pushNotificationsGatewayUrl,
  AppSettings.pushNotificationsPusherFormat,
  AppSettings.fallbackLiveKitInstance,
  AppSettings.spaceNavigation,
  AppSettings.showFoldersAfterSpaces,
  AppSettings.showTabUnreadCounts,
  AppSettings.unarchiveOnMention,
  AppSettings.presenceAway,
  AppSettings.defaultDisappearSeconds,
};

bool _isHttpsUrl(Object? value) =>
    value is String && Uri.tryParse(value)?.scheme == 'https';

bool _intIn(Object? value, int min, int max) =>
    value is int && value >= min && value <= max;

/// Privacy settings where config.json may only choose the more private value,
/// and links that are opened with launchUrlString (must be https).
final webValidatedSettings = <AppSettings<Object?>, bool Function(Object?)>{
  AppSettings.sendTypingNotifications: (value) => value == false,
  AppSettings.sendPublicReadReceipts: (value) => value == false,
  AppSettings.shareOnlineStatus: (value) => value == false,
  AppSettings.appearOffline: (value) => value == true,
  AppSettings.autoSendErrorReports: (value) => value == false,
  AppSettings.shareKeysWith: (value) =>
      value is String &&
      value != ShareKeysWith.all.name &&
      ShareKeysWith.values.any((share) => share.name == value),
  AppSettings.fontSizeFactor: (value) =>
      value is double && value.isFinite && value >= 0.5 && value <= 3.0,
  AppSettings.chatWallpaperPreset: isWallpaperPresetId,
  AppSettings.chatWallpaperLocal: (value) => value == false,
  AppSettings.bubbleCorners: (value) => BubbleCorners.byName(value) != null,
  AppSettings.textMessageMaxLength: (value) => _intIn(value, 1, 65536),
  AppSettings.messagePreviewMaxLines: (value) => _intIn(value, 0, 500),
  AppSettings.sendTimelineEventTimeout: (value) => _intIn(value, 5, 120),
  AppSettings.audioRecordingNumChannels: (value) => _intIn(value, 1, 2),
  AppSettings.audioRecordingBitRate: (value) => _intIn(value, 6000, 510000),
  AppSettings.audioRecordingSamplingRate: (value) => _intIn(value, 8000, 48000),
  AppSettings.website: _isHttpsUrl,
  AppSettings.logoUrl: _isHttpsUrl,
  AppSettings.privacyPolicy: _isHttpsUrl,
  AppSettings.tos: _isHttpsUrl,
  AppSettings.repositoryUrl: (value) =>
      value is String && RepoLinks.parse(value) != null,
  AppSettings.koFiUrl: isAcceptableSupportUrl,
  AppSettings.buyMeACoffeeUrl: isAcceptableSupportUrl,
};

const webAllowedSettings = <AppSettings<Object?>>{
  AppSettings.applicationName,
  AppSettings.defaultHomeserver,
  AppSettings.presetHomeserver,
  AppSettings.welcomeText,
  AppSettings.colorSchemeSeedInt,
  AppSettings.accentHue,
  AppSettings.reduceTransparency,
  AppSettings.glassMode,
  AppSettings.enableMatrixNativeOIDC,
  AppSettings.enableSoftLogout,
  AppSettings.checkForUpdates,
  AppSettings.repositoryConfirmed,
  AppSettings.chatFilter,
  AppSettings.emojiSuggestionLocale,
  AppSettings.benchmarksInLogs,
  AppSettings.audioRecordingAutoGain,
  AppSettings.audioRecordingEchoCancel,
  AppSettings.audioRecordingNoiseSuppress,
  AppSettings.renderHtml,
  AppSettings.hideRedactedEvents,
  AppSettings.hideUnknownEvents,
  AppSettings.autoplayImages,
  AppSettings.swipeRightToLeftToReply,
  AppSettings.sendOnEnter,
  AppSettings.callsEnabled,
  AppSettings.displayChatDetailsColumn,
  AppSettings.webNotificationSound,
  AppSettings.hideRoomsInSpaces,
  AppSettings.showThumbnailsInTimeline,
  AppSettings.doubleTapToReact,
  AppSettings.doubleTapReaction,
};

Map<String, Object?> filterPlatformConfiguration(
  Map<String, Object?> config,
  PlatformConfigSource source,
) {
  final result = <String, Object?>{};
  for (final entry in config.entries) {
    final setting = AppSettings.values.firstWhereOrNull(
      (setting) => setting.name == entry.key,
    );
    final isAllowed =
        setting != null &&
        !runtimeStateSettings.contains(setting) &&
        (source == PlatformConfigSource.mdm ||
            (!webDeniedSettings.contains(setting) &&
                (webAllowedSettings.contains(setting) ||
                    (webValidatedSettings[setting]?.call(entry.value) ??
                        false))));
    if (isAllowed) {
      result[entry.key] = entry.value;
      continue;
    }
    Logs().w('[ConfigLoader] Ignoring "${entry.key}" (${source.name})');
  }
  return result;
}

extension AppSettingsBoolNExtension on AppSettings<bool?> {
  bool? get value {
    final value = Result(() => AppSettings.store.getBool(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value;
  }

  Future<void> setItem(bool value) async {
    await AppSettings.store.setBool(key, value);
    _notifyChanged();
  }
}

extension AppSettingsBoolExtension on AppSettings<bool> {
  bool get value {
    final value = Result(() => AppSettings.store.getBool(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(bool value) async {
    await AppSettings.store.setBool(key, value);
    _notifyChanged();
  }
}

extension AppSettingsStringExtension on AppSettings<String> {
  String get value {
    final value = Result(() => AppSettings.store.getString(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(String value) async {
    await AppSettings.store.setString(key, value);
    _notifyChanged();
  }
}

extension AppSettingsIntExtension on AppSettings<int> {
  int get value {
    final value = Result(() => AppSettings.store.getInt(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(int value) async {
    await AppSettings.store.setInt(key, value);
    _notifyChanged();
  }
}

extension AppSettingsDoubleExtension on AppSettings<double> {
  double get value {
    final value = Result(() => AppSettings.store.getDouble(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(double value) async {
    await AppSettings.store.setDouble(key, value);
    _notifyChanged();
  }
}

extension AppSettingsStringListExtension on AppSettings<List<String>> {
  List<String> get value {
    final value = Result(() => AppSettings.store.getStringList(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(List<String> value) async {
    await AppSettings.store.setStringList(key, value);
    _notifyChanged();
  }
}
