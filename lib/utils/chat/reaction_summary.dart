// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/design_constants.dart';

class ReactionEntry {
  static const maxKeyLength = 128;
  static const maxReactors = 200;
  static final _serverName = RegExp(r'^[A-Za-z0-9.-]+$');
  static final _mediaId = RegExp(r'^[A-Za-z0-9_-]+$');

  final String key;
  int count = 0;
  bool own = false;
  final List<User> reactors = [];

  ReactionEntry(this.key);

  /// Only a well formed mxc URI is fetched, anything else is shown as text.
  Uri? get imageUri {
    final uri = Uri.tryParse(key);
    if (uri == null || uri.scheme != 'mxc') return null;
    if (!_serverName.hasMatch(uri.host)) return null;
    if (uri.pathSegments.length != 1 ||
        !_mediaId.hasMatch(uri.pathSegments.single)) {
      return null;
    }
    return uri;
  }
}

class ReactionSummary {
  final List<ReactionEntry> entries;
  final int hiddenKeys;

  const ReactionSummary(this.entries, this.hiddenKeys);
}

/// Groups reactions by key. Senders control the number of keys, their length
/// and which of them are image URIs, so all three are capped.
ReactionSummary summarizeReactions(
  Iterable<Event> reactionEvents,
  String? ownUserId, {
  int maxKeys = AppChat.maxReactionKeys,
}) {
  final map = <String, ReactionEntry>{};
  final seen = <String>{};
  for (final event in reactionEvents) {
    final key = event.content
        .tryGetMap<String, Object?>('m.relates_to')
        ?.tryGet<String>('key');
    if (key == null || key.isEmpty || key.length > ReactionEntry.maxKeyLength) {
      continue;
    }
    if (!seen.add('${event.senderId}\n$key')) continue;
    final entry = map.putIfAbsent(key, () => ReactionEntry(key));
    entry.count++;
    entry.own |= event.senderId == ownUserId;
    if (entry.reactors.length < ReactionEntry.maxReactors) {
      entry.reactors.add(event.senderFromMemoryOrFallback);
    }
  }
  final sorted = map.values.toList().sortedByCompare(
    (entry) => entry.count,
    (a, b) => b.compareTo(a),
  );
  return ReactionSummary(
    sorted.take(maxKeys).toList(),
    sorted.length > maxKeys ? sorted.length - maxKeys : 0,
  );
}
