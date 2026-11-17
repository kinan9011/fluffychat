// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/retention/retention_policy.dart';
import 'package:matrix/matrix.dart';

extension VisibleInGuiExtension on List<Event> {
  List<Event> filterByVisibleInGui({
    String? exceptionEventId,
    String? threadId,
    RetentionPolicy? retention,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return where((event) {
      if (event.eventId != exceptionEventId &&
          retention?.hides(event, at) == true) {
        return false;
      }
      if (threadId != null &&
          event.relationshipType != RelationshipTypes.reaction) {
        if ((event.relationshipType != RelationshipTypes.thread ||
                event.relationshipEventId != threadId) &&
            event.eventId != threadId) {
          return false;
        }
      } else if (event.relationshipType == RelationshipTypes.thread) {
        return false;
      }
      return event.isVisibleInGui || event.eventId == exceptionEventId;
    }).toList();
  }
}

extension IsStateExtension on Event {
  bool get isVisibleInGui =>
      // always filter out edit and reaction relationships
      !{
        RelationshipTypes.edit,
        RelationshipTypes.reaction,
      }.contains(relationshipType) &&
      // always filter out m.key.* and other known but unimportant events
      !isKnownHiddenStates &&
      // event types to hide: redaction and reaction events
      // if a reaction has been redacted we also want it to be hidden in the timeline
      !{EventTypes.Reaction, EventTypes.Redaction}.contains(type) &&
      // if we enabled to hide all redacted events, don't show those
      (!AppSettings.hideRedactedEvents.value || !redacted) &&
      // if we enabled to hide all unknown events, don't show those
      (!AppSettings.hideUnknownEvents.value ||
          isEventTypeKnown ||
          type == RetentionPolicy.eventType);

  bool get isState => !{EventTypes.Message, EventTypes.Sticker}.contains(type);

  bool get isCollapsedState =>
      !{
        EventTypes.Message,
        EventTypes.Sticker,
        EventTypes.RoomCreate,
        EventTypes.RoomTombstone,
      }.contains(type) &&
      !isUndecryptable;

  /// Shown as a bubble ("Waiting for this message"), never folded away.
  bool get isUndecryptable =>
      type == EventTypes.Encrypted &&
      !redacted &&
      messageType == MessageTypes.BadEncrypted;

  bool get isKnownHiddenStates =>
      {PollEventContent.responseType}.contains(type) ||
      type.startsWith('m.key.verification.');
}
