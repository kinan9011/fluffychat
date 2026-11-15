// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:matrix/matrix.dart';

const archivedTag = 'im.fluffychat.archived';

extension ChatListRoomExtension on Room {
  bool get isJoinedSpace => isSpace && membership == Membership.join;

  bool get isArchivedChat =>
      membership == Membership.join && tags.containsKey(archivedTag);

  Future<void> setArchivedChat(bool archived) =>
      archived ? addTag(archivedTag) : removeTag(archivedTag);

  double? get pinOrder {
    final order = tags[TagType.favourite]?.order;
    if (order == null || !order.isFinite || order < 0 || order > 1) {
      return null;
    }
    return order;
  }
}

double pinOrderForNew(Iterable<double?> existing) {
  final valid = existing
      .whereType<double>()
      .where((order) => order.isFinite && order >= 0 && order <= 1)
      .toList();
  if (valid.isEmpty) return 0.5;
  final order = valid.reduce(min) / 2;
  return order < 1e-9 ? 0.0 : order;
}
