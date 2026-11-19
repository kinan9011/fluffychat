// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/server_capabilities/server_capabilities.dart';

/// The rows of the Homeserver features screen, in the order of the mockup.
const homeserverFeatureOrder = [
  ServerFeature.slidingSync,
  ServerFeature.retention,
  ServerFeature.qrLogin,
  ServerFeature.threadNotifications,
  ServerFeature.delayedEvents,
  ServerFeature.groupCalls,
];

String featureTitle(L10n l10n, ServerFeature feature) => switch (feature) {
  ServerFeature.slidingSync => l10n.featureSlidingSync,
  ServerFeature.retention => l10n.featureDisappearing,
  ServerFeature.qrLogin => l10n.featureQrSignIn,
  ServerFeature.threadNotifications => l10n.featureThreadNotifications,
  ServerFeature.delayedEvents => l10n.featureScheduling,
  ServerFeature.groupCalls => l10n.featureGroupCalls,
  ServerFeature.serverSideSearchE2ee => '',
};

String featureDescription(L10n l10n, ServerFeature feature) =>
    switch (feature) {
      ServerFeature.slidingSync => l10n.featureSlidingSyncDesc,
      ServerFeature.retention => l10n.featureDisappearingDesc,
      ServerFeature.qrLogin => l10n.featureQrSignInDesc,
      ServerFeature.threadNotifications => l10n.featureThreadNotificationsDesc,
      ServerFeature.delayedEvents => l10n.featureSchedulingDesc,
      ServerFeature.groupCalls => l10n.featureGroupCallsDesc,
      ServerFeature.serverSideSearchE2ee => '',
    };

String supportLabel(L10n l10n, FeatureSupport support) => switch (support) {
  FeatureSupport.supported => l10n.featureSupported,
  FeatureSupport.partial => l10n.featurePartial,
  FeatureSupport.unsupported => l10n.featureNotSetUp,
  FeatureSupport.unknown => l10n.featureUnknown,
};

class HomeserverInfo {
  const HomeserverInfo({
    required this.domain,
    this.software,
    this.version,
    this.uploadLimitBytes,
    this.online,
  });

  final String domain;
  final String? software;
  final String? version;
  final int? uploadLimitBytes;
  final bool? online;
}

/// `GET /_matrix/federation/v1/version` answers `{server: {name, version}}`.
/// The strings come from the server: both must be short strings or the
/// whole answer is ignored.
({String name, String version})? parseServerVersion(Object? json) {
  if (json is! Map) return null;
  final server = json['server'];
  if (server is! Map) return null;
  final name = server['name'];
  final version = server['version'];
  if (name is! String || version is! String) return null;
  if (name.length > 256 || version.length > 256) return null;
  final cleanName = safeDisplayText(name);
  if (cleanName.isEmpty) return null;
  return (name: cleanName, version: safeDisplayText(version));
}

/// Null for anything that is not a positive size below 1 TiB.
String? formatUploadLimit(int? bytes) {
  if (bytes == null || bytes <= 0 || bytes > (1 << 40)) return null;
  String trim(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toString();
  }

  if (bytes < 1000 * 1000) return '${trim(bytes / 1000)} KB';
  if (bytes < 1000 * 1000 * 1000) return '${trim(bytes / 1000000)} MB';
  return '${trim(bytes / 1000000000)} GB';
}

/// Which hosts the version lookup may ask: the homeserver itself, its domain
/// or a subdomain of either. A well-known file must not make this app talk to
/// any other machine.
bool isTrustedFederationHost(
  String host, {
  required String userDomain,
  required String? homeserverHost,
}) {
  final h = host.toLowerCase();
  if (h.isEmpty || h.length > 253) return false;
  bool within(String? root) {
    if (root == null || root.isEmpty) return false;
    final r = root.toLowerCase();
    return h == r || h.endsWith('.$r');
  }

  return within(userDomain) || within(homeserverHost);
}

/// The plain text a user can send to their admin. It names the server and the
/// state of each feature and nothing about the user: no account, device,
/// token, address or local setting.
String buildAdminReport({
  required HomeserverInfo info,
  required ServerCapabilities caps,
  required String appName,
  required L10n l10n,
}) {
  final domain = safeDisplayText(info.domain, maxGraphemes: 128);
  final software = info.software == null
      ? null
      : '${safeDisplayText(info.software!)} ${safeDisplayText(info.version ?? '')}'
            .trim();
  final limit = formatUploadLimit(info.uploadLimitBytes);
  final lines = <String>[
    l10n.adminReportTitle,
    '',
    '${l10n.settingsHomeserver}: $domain',
    if (software != null && software.isNotEmpty) software,
    if (limit != null) l10n.homeserverUploadLimit(limit),
    '',
    l10n.homeserverFeatures,
    for (final feature in homeserverFeatureOrder)
      '${featureTitle(l10n, feature)}: ${supportLabel(l10n, caps[feature])}',
    '',
    l10n.adminReportFooter(safeDisplayText(appName)),
  ];
  return lines.join('\n');
}
