// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

final _roomId = RegExp(r'^!(?:[^:\s]{1,255}:[^\s]{1,255}|[A-Za-z0-9_\-]{43})$');

/// A room id: `!local:server`, or `!` plus 43 url-safe base64 characters
/// (room version 12 has no server part).
bool isMatrixRoomId(String id) => _roomId.hasMatch(id);

final _eventId = RegExp(
  r'^\$[A-Za-z0-9+/=_.\-]{1,255}(:[A-Za-z0-9.\-\[\]:]{1,255})?$',
);

/// An event id as it may be put into a route: `$` plus url-safe characters.
bool isMatrixEventId(Object? value) =>
    value is String &&
    value.isValidMatrixIdStrict() &&
    _eventId.hasMatch(value);
