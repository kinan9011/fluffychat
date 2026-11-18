// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_room_id.dart';
import 'package:flutter/foundation.dart';

/// The spaces the user went through to get to this overview. A space that is
/// already on the trail cannot be entered again (cycle) and the trail stops
/// at [maxDepth].
@immutable
class SpaceTrail {
  const SpaceTrail([this.ids = const []]);

  static const maxDepth = 8;

  final List<String> ids;

  /// The trail is a comma list in the route: an id with a comma would be cut
  /// apart when it is read back and so escape the cycle and depth guards.
  static bool isSpaceId(String id) => isMatrixRoomId(id) && !id.contains(',');

  bool canEnter(String spaceId) =>
      isSpaceId(spaceId) && !ids.contains(spaceId) && ids.length < maxDepth;

  SpaceTrail enter(String spaceId) => SpaceTrail([...ids, spaceId]);

  /// The trail of a route query: valid room ids only, no repeats, at most
  /// [maxDepth] of them.
  factory SpaceTrail.parse(String? query) {
    if (query == null || query.isEmpty) return const SpaceTrail();
    final ids = <String>[];
    for (final part in query.split(',')) {
      if (ids.length >= maxDepth) break;
      if (!isSpaceId(part) || ids.contains(part)) continue;
      ids.add(part);
    }
    return SpaceTrail(ids);
  }

  String? encode() => ids.isEmpty ? null : ids.join(',');
}
