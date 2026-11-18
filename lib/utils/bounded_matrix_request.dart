// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/bounded_body.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// A request to the own homeserver whose answer is read with a size cap. The
/// SDK buffers and decodes whatever the server sends; `/search`,
/// `/hierarchy` and `/publicRooms` relay data of other servers, so their
/// answers are not trusted to be small. Throws when the answer is larger than
/// [maxBytes], is not a success or is not a JSON object.
Future<Map<String, Object?>> boundedMatrixJson(
  Client client,
  String method,
  String path, {
  required int maxBytes,
  Map<String, String>? query,
  Map<String, Object?>? body,
}) async {
  final base = client.homeserver;
  final token = client.accessToken;
  if (base == null || token == null) throw const FormatException('no session');
  final request = http.Request(
    method,
    base.resolveUri(Uri(path: path, queryParameters: query)),
  )..headers['authorization'] = 'Bearer $token';
  if (body != null) {
    request.headers['content-type'] = 'application/json';
    request.bodyBytes = utf8.encode(jsonEncode(body));
  }
  final text = await readBoundedResponse(
    client.httpClient,
    request,
    maxBytes: maxBytes,
  );
  if (text == null) throw const FormatException('answer refused');
  final json = jsonDecode(text);
  if (json is! Map<String, Object?>) throw const FormatException('not a map');
  return json;
}
