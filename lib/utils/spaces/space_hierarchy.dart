// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/utils/bounded_matrix_request.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/spaces/space_trail.dart';

@immutable
class HierarchyChild {
  const HierarchyChild({
    required this.roomId,
    required this.name,
    required this.topic,
    required this.alias,
    required this.avatar,
    required this.isSpace,
    required this.memberCount,
    required this.joinRule,
    required this.childCount,
  });

  final String roomId;

  /// Cleaned, null when the room has no readable name.
  final String? name;
  final String? topic;
  final String? alias;
  final Uri? avatar;
  final bool isSpace;
  final int memberCount;
  final String? joinRule;
  final int childCount;
}

@immutable
class HierarchyPage {
  const HierarchyPage(this.children, this.nextBatch, {this.dropped = 0});

  static const empty = HierarchyPage([], null);

  final List<HierarchyChild> children;
  final String? nextBatch;

  /// Raw entries that were not looked at because the page had too many.
  final int dropped;
}

/// The answer of `/hierarchy` is untrusted: any member of a public space
/// controls what the server relays. Every field is type-checked and cut,
/// entries are capped, `children_state` is never read beyond its length.
abstract final class HierarchyParser {
  static const maxEntriesPerPage = 200;
  static const maxTotalEntries = 500;
  static const maxPages = 10;
  static const maxNameChars = 100;
  static const maxTopicChars = 400;
  static const maxAliasChars = 255;
  static const maxAvatarChars = 255;
  static const maxMembers = 10000000;
  static const maxChildCount = 10000;
  static const maxTokenChars = 512;

  static const _joinRules = {
    'public',
    'knock',
    'invite',
    'private',
    'restricted',
    'knock_restricted',
  };

  static final _alias = RegExp(r'^#[^\s:]+:[^\s]+$');

  static HierarchyPage parse(
    Object? json, {
    required String rootId,
    Set<String> seen = const {},
  }) {
    if (json is! Map) return HierarchyPage.empty;
    final rooms = json['rooms'];
    if (rooms is! List) return HierarchyPage.empty;
    final children = <HierarchyChild>[];
    final ids = <String>{};
    for (final raw in rooms.take(maxEntriesPerPage)) {
      final child = _child(raw, rootId);
      if (child == null) continue;
      if (seen.contains(child.roomId) || !ids.add(child.roomId)) continue;
      children.add(child);
    }
    final token = json['next_batch'];
    return HierarchyPage(
      children,
      token is String && token.isNotEmpty && token.length <= maxTokenChars
          ? token
          : null,
      dropped: rooms.length > maxEntriesPerPage
          ? rooms.length - maxEntriesPerPage
          : 0,
    );
  }

  static String? _text(Object? value, int max) {
    if (value is! String) return null;
    final text = safeDisplayText(value, maxGraphemes: max);
    return text.isEmpty ? null : text;
  }

  static HierarchyChild? _child(Object? raw, String rootId) {
    if (raw is! Map) return null;
    final roomId = raw['room_id'];
    if (roomId is! String ||
        roomId == rootId ||
        !SpaceTrail.isSpaceId(roomId)) {
      return null;
    }
    final type = raw['room_type'];
    if (type != null && type != 'm.space') return null;
    final members = raw['num_joined_members'];
    final joinRule = raw['join_rule'];
    final state = raw['children_state'];
    return HierarchyChild(
      roomId: roomId,
      name: _text(raw['name'], maxNameChars),
      topic: _text(raw['topic'], maxTopicChars),
      alias: _aliasOf(raw['canonical_alias']),
      avatar: _avatar(raw['avatar_url']),
      isSpace: type == 'm.space',
      memberCount: members is int ? members.clamp(0, maxMembers) : 0,
      joinRule: joinRule is String && _joinRules.contains(joinRule)
          ? joinRule
          : null,
      childCount: state is List ? state.length.clamp(0, maxChildCount) : 0,
    );
  }

  static String? _aliasOf(Object? value) {
    if (value is! String || value.length > maxAliasChars) return null;
    if (!_alias.hasMatch(value)) return null;
    return safeDisplayText(value, maxGraphemes: maxAliasChars) == value
        ? value
        : null;
  }

  static Uri? _avatar(Object? value) {
    if (value is! String || value.length > maxAvatarChars) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'mxc' ||
        uri.host.isEmpty ||
        uri.path.length < 2 ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }
}

/// The pages of one overview: remembers what it has shown and stops at the
/// page and entry caps.
class HierarchyAccumulator {
  final _seen = <String>{};
  final children = <HierarchyChild>[];
  var pages = 0;
  var capped = false;

  bool get exhausted => pages >= HierarchyParser.maxPages || capped;

  /// Adds [page] and returns what was new. Entries beyond the total cap are
  /// dropped and [capped] is set.
  List<HierarchyChild> add(HierarchyPage page) {
    pages++;
    final added = <HierarchyChild>[];
    for (final child in page.children) {
      if (children.length >= HierarchyParser.maxTotalEntries) {
        capped = true;
        break;
      }
      if (!_seen.add(child.roomId)) continue;
      children.add(child);
      added.add(child);
    }
    if (children.length >= HierarchyParser.maxTotalEntries &&
        page.nextBatch != null) {
      capped = true;
    }
    return added;
  }

  Set<String> get seen => Set.unmodifiable(_seen);
}

/// One page of `/hierarchy`: direct children only (`max_depth` 1), the
/// subspaces are entered, not flattened into the list. The answer is read
/// with a cap: it carries `children_state` of rooms of other servers.
const maxHierarchyBytes = 8 * 1024 * 1024;

Future<Object?> fetchHierarchyPage(
  Client client,
  String spaceId, {
  String? from,
  int limit = 50,
}) => boundedMatrixJson(
  client,
  'GET',
  '_matrix/client/v1/rooms/${Uri.encodeComponent(spaceId)}/hierarchy',
  maxBytes: maxHierarchyBytes,
  query: {
    'suggested_only': 'false',
    'limit': '$limit',
    'max_depth': '1',
    'from': ?from,
  },
);
