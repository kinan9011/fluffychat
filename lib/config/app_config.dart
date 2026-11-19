// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

abstract class AppConfig {
  static const Color primaryColor = Color(0xFF5473D2);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'com.swovo.odango://chat/';
  static const String appleAppGroupId = 'group.com.swovo.odango';
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'odango_push';
  static const String pushNotificationsAppId = 'com.swovo.odango';
  static const double borderRadius = 18.0;
  static const double spaceBorderRadius = 11.0;
  static const double columnWidth = 360.0;

  static const String appId = 'com.swovo.odango';
  static const String appOpenUrlScheme = 'com.swovo.odango';
  static const String appSsoUrlScheme = 'de.swovo.odango';
  // Identifies the notification activation callback on Windows. Never change!
  static const String windowsNotificationGuid =
      '3669988d-118c-4fff-a1f1-98ae7cbbbeaa';

  static const String upstreamRepoUrl =
      'https://github.com/krille-chan/fluffychat';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
  static const String pushHelperCrashReportKey = 'push_helper_crash_report';

  static const String vodozemacVersion = '0.9.0';
}
