// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:odango/utils/server_capabilities/server_capabilities.dart';

/// Whether the call entry points are shown. An unknown answer counts as not
/// available: nothing call related is shown until the server is known to
/// support calls. A partial answer is the user's own fallback LiveKit
/// instance, which calls really use.
bool callsAvailable({
  required bool enabled,
  required ServerCapabilities capabilities,
}) =>
    enabled &&
    switch (capabilities[ServerFeature.groupCalls]) {
      FeatureSupport.supported || FeatureSupport.partial => true,
      FeatureSupport.unsupported || FeatureSupport.unknown => false,
    };

enum CallNotificationPlan { ring, notify, drop }

/// What an incoming event does to the user. Without calls a MatrixRTC
/// notification is dropped entirely: no CallKit, no dialog and no
/// notification with an Enter call action.
CallNotificationPlan planCallNotification(
  Event event, {
  required bool callsAvailable,
  required bool canRing,
}) {
  if (!event.isRtcNotificationEvent) return CallNotificationPlan.notify;
  if (!callsAvailable) return CallNotificationPlan.drop;
  final ring =
      event.tryParseRtcNotificationContent()?.notificationType == .ring;
  return ring && canRing
      ? CallNotificationPlan.ring
      : CallNotificationPlan.notify;
}
