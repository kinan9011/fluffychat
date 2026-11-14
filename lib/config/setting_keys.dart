// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:ui' show Color;

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:fluffychat/utils/oklch.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:managed_configurations/managed_configurations.dart';
import 'package:matrix/matrix.dart' show ShareKeysWith;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultColorSchemeSeed = 0xFF5625BA;

enum AppSettings<T> {
  textMessageMaxLength<int>('textMessageMaxLength', 16384),

  /// Max lines for unselected HTML/text bubbles; 0 = unlimited (no fade).
  messagePreviewMaxLines<int>('chat.fluffy.message_preview_max_lines', 50),
  audioRecordingNumChannels<int>('audioRecordingNumChannels', 1),
  audioRecordingAutoGain<bool>('audioRecordingAutoGain', true),
  audioRecordingEchoCancel<bool>('audioRecordingEchoCancel', false),
  audioRecordingNoiseSuppress<bool>('audioRecordingNoiseSuppress', true),
  audioRecordingBitRate<int>('audioRecordingBitRate', 64000),
  audioRecordingSamplingRate<int>('audioRecordingSamplingRate', 48000),
  showNoGoogle<bool>('chat.fluffy.show_no_google', false),
  unifiedPushRegistered<bool>('chat.fluffy.unifiedpush.registered', false),
  unifiedPushEndpoint<String>('chat.fluffy.unifiedpush.endpoint', ''),
  pushNotificationsGatewayUrl<String>(
    'pushNotificationsGatewayUrl',
    'https://push.fluffychat.im/_matrix/push/v1/notify',
  ),
  pushNotificationsPusherFormat<String>(
    'pushNotificationsPusherFormat',
    'event_id_only',
  ),
  renderHtml<bool>('chat.fluffy.renderHtml', true),
  fontSizeFactor<double>('chat.fluffy.font_size_factor', 1.0),
  hideRedactedEvents<bool>('chat.fluffy.hideRedactedEvents', false),
  hideUnknownEvents<bool>('chat.fluffy.hideUnknownEvents', true),
  autoplayImages<bool>('chat.fluffy.autoplay_images', true),
  sendTypingNotifications<bool>('chat.fluffy.send_typing_notifications', true),
  sendPublicReadReceipts<bool>('chat.fluffy.send_public_read_receipts', true),
  swipeRightToLeftToReply<bool>('chat.fluffy.swipeRightToLeftToReply', true),
  sendOnEnter<bool>('chat.fluffy.send_on_enter', false),
  shareKeysWith<String>('chat.fluffy.share_keys_with_2', 'all'),
  noEncryptionWarningShown<bool>(
    'chat.fluffy.no_encryption_warning_shown',
    false,
  ),
  databaseUnencryptedClients<List<String>>(
    'chat.fluffy.database_unencrypted_clients',
    [],
  ),
  databaseQuarantinedClients<List<String>>(
    'chat.fluffy.database_quarantined_clients',
    [],
  ),
  databaseUnencryptedNoticeDismissed<bool>(
    'chat.fluffy.database_unencrypted_notice_dismissed',
    false,
  ),
  displayChatDetailsColumn('chat.fluffy.display_chat_details_column', false),
  // AppConfig-mirrored settings
  applicationName<String>('chat.fluffy.application_name', 'FluffyChat'),
  defaultHomeserver<String>('chat.fluffy.default_homeserver', 'matrix.org'),
  // colorSchemeSeed stored as ARGB int
  colorSchemeSeedInt<int>(
    'chat.fluffy.color_scheme_seed',
    defaultColorSchemeSeed,
  ),
  accentHue<int>('chat.fluffy.accent_hue', 268),
  reduceTransparency<bool>('chat.fluffy.reduce_transparency', false),
  callsEnabled<bool>('chat.fluffy.calls_enabled', true),
  emojiSuggestionLocale<String>('emoji_suggestion_locale', ''),
  enableSoftLogout<bool>('chat.fluffy.enable_soft_logout', true),
  enableMatrixNativeOIDC<bool>('chat.fluffy.enable_matrix_native_oidc', true),
  presetHomeserver<String>('chat.fluffy.preset_homeserver', ''),
  welcomeText<String>('chat.fluffy.welcome_text', ''),
  website<String>('chat.fluffy.website_url', 'https://fluffychat.im'),
  logoUrl<String>(
    'chat.fluffy.logo_url',
    'https://fluffychat.im/assets/favicon.png',
  ),
  privacyPolicy<String>(
    'chat.fluffy.privacy_policy_url',
    'https://fluffychat.im/privacy',
  ),
  tos<String>('chat.fluffy.tos_url', 'https://fluffychat.im/tos'),
  sendTimelineEventTimeout<int>('chat.fluffy.send_timeline_event_timeout', 15),
  webNotificationSound<bool>('chat.fluffy.web_notification_sound', true),
  chatFilter<String>('chat.fluffy.chat_filter', 'allChats'),
  hideRoomsInSpaces<bool>('chat.fluffy.hideRoomsInSpaces', false),
  showThumbnailsInTimeline<bool>('chat.fluffy.showThumbnailsInTimeline', true),
  doubleTapToReact<bool>('chat.fluffy.double_tap_to_react', false),
  doubleTapReaction<String>('chat.fluffy.double_tap_reaction', '❤️'),
  benchmarksInLogs<bool>('chat.fluffy.benchmarks_in_logs', false),
  autoSendErrorReports<bool?>('chat.fluffy.auto_send_eror_reports', null),
  knownErrorHashes<List<String>>('chat.fluffy.known_crash_hashes', []),
  checkForUpdates<bool>('chat.fluffy.check_for_updates', true),
  lastUpdateCheckDate<String>('chat.fluffy.last_update_check_date', ''),
  fallbackLiveKitInstance<String>('chat.fluffy.fallback_live_kit_instance', '');

  final String key;
  final T _defaultValue;

  const AppSettings(this.key, this._defaultValue);

  static SharedPreferences get store => _store!;
  static SharedPreferences? _store;

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
    await store.remove('chat.fluffy.database_unencrypted');
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
  AppSettings.autoSendErrorReports: (value) => value == false,
  AppSettings.shareKeysWith: (value) =>
      value is String &&
      value != ShareKeysWith.all.name &&
      ShareKeysWith.values.any((share) => share.name == value),
  AppSettings.fontSizeFactor: (value) =>
      value is double && value.isFinite && value >= 0.5 && value <= 3.0,
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
};

const webAllowedSettings = <AppSettings<Object?>>{
  AppSettings.applicationName,
  AppSettings.defaultHomeserver,
  AppSettings.presetHomeserver,
  AppSettings.welcomeText,
  AppSettings.colorSchemeSeedInt,
  AppSettings.accentHue,
  AppSettings.reduceTransparency,
  AppSettings.enableMatrixNativeOIDC,
  AppSettings.enableSoftLogout,
  AppSettings.checkForUpdates,
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

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
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

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
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

  Future<void> setItem(String value) => AppSettings.store.setString(key, value);
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

  Future<void> setItem(int value) => AppSettings.store.setInt(key, value);
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

  Future<void> setItem(double value) => AppSettings.store.setDouble(key, value);
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

  Future<void> setItem(List<String> value) =>
      AppSettings.store.setStringList(key, value);
}
