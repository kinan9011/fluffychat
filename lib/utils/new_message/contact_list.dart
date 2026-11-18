// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// A direct chat partner as the new message page needs it.
@immutable
class ContactSource {
  const ContactSource({
    required this.userId,
    required this.name,
    required this.lastActivity,
  });

  final String userId;
  final String name;
  final DateTime lastActivity;
}

@immutable
class ContactEntry {
  const ContactEntry({
    required this.userId,
    required this.name,
    required this.status,
    required this.online,
    required this.lastSeen,
  });

  final String userId;
  final String name;

  /// The status text of the other person, cleaned; null when there is none.
  final String? status;
  final bool online;
  final DateTime? lastSeen;
}

/// The people the user already chats with, most recently seen first.
/// Presence is only what the client already holds from sync: nothing is
/// requested to build this list.
abstract final class ContactList {
  static const maxContacts = 200;
  static const maxStatusChars = 80;

  static List<ContactEntry> build(
    Iterable<ContactSource> sources, {
    required Map<String, CachedPresence> presences,
    required String ownUserId,
  }) {
    final seen = <String>{};
    final entries = <ContactEntry>[];
    for (final source in sources) {
      if (source.userId == ownUserId || !seen.add(source.userId)) continue;
      final presence = presences[source.userId];
      final status = presence?.statusMsg;
      final cleaned = status == null
          ? null
          : safeDisplayText(status, maxGraphemes: maxStatusChars);
      entries.add(
        ContactEntry(
          userId: source.userId,
          name: safeDisplayText(source.name, maxGraphemes: 64),
          status: cleaned == null || cleaned.isEmpty ? null : cleaned,
          online: presence?.presence == PresenceType.online,
          lastSeen: presence?.lastActiveTimestamp,
        ),
      );
    }
    final activity = {
      for (final source in sources) source.userId: source.lastActivity,
    };
    entries.sort((a, b) {
      final seenA = a.lastSeen;
      final seenB = b.lastSeen;
      if (seenA != null && seenB != null) return seenB.compareTo(seenA);
      if (seenA != null) return -1;
      if (seenB != null) return 1;
      return activity[b.userId]!.compareTo(activity[a.userId]!);
    });
    return entries.take(maxContacts).toList();
  }
}
