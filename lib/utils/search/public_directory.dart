// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/bounded_matrix_request.dart';
import 'package:matrix/matrix.dart';

const maxDirectoryBytes = 2 * 1024 * 1024;

/// One page of the public room directory of [server] (the own homeserver when
/// null), asked through the own homeserver. [term] is sent to that directory
/// as the search word; without one the whole directory is listed.
Future<QueryPublicRoomsResponse> queryPublicDirectory(
  Client client, {
  String? server,
  String term = '',
  String? since,
  int limit = 20,
}) async => QueryPublicRoomsResponse.fromJson(
  await boundedMatrixJson(
    client,
    'POST',
    '_matrix/client/v3/publicRooms',
    maxBytes: maxDirectoryBytes,
    query: {'server': ?server},
    body: {
      if (term.isNotEmpty) 'filter': {'generic_search_term': term},
      'limit': limit,
      'since': ?since,
    },
  ),
);
