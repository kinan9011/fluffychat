// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/retention/retention_policy.dart';
import 'package:odango/utils/server_capabilities/server_capabilities.dart';

String formatRetention(L10n l10n, Duration lifetime) {
  if (lifetime == const Duration(days: 7)) return l10n.retentionWeek;
  if (lifetime == const Duration(days: 30)) return l10n.retentionMonth;
  if (lifetime.inHours % 24 == 0 && lifetime.inDays >= 1) {
    return l10n.retentionDays(lifetime.inDays);
  }
  return l10n.retentionHours(lifetime.inHours);
}

/// The service message of an `m.room.retention` state event.
String retentionServiceText(L10n l10n, Event event) {
  final name = safeDisplayText(
    event.senderFromMemoryOrFallback.calcDisplayname(),
  );
  final policy = RetentionPolicy.fromContent(event.content);
  if (policy != null) {
    return l10n.retentionSetBy(name, formatRetention(l10n, policy.maxLifetime));
  }
  return switch (RetentionPolicy.stateOf(event.content)) {
    RetentionState.off => l10n.retentionTurnedOff(name),
    _ => l10n.retentionChanged(name),
  };
}

/// What the server is known to do about old messages. Unknown is said as
/// unknown, never as a promise.
String retentionServerNote(L10n l10n, FeatureSupport support) =>
    switch (support) {
      FeatureSupport.supported => l10n.retentionServerSupported,
      FeatureSupport.unsupported => l10n.retentionServerUnsupported,
      FeatureSupport.partial ||
      FeatureSupport.unknown => l10n.retentionServerUnknown,
    };
