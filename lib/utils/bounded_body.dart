// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart';

/// GETs [url] and returns the body as text, or null when the answer is not a
/// success or is longer than [maxBytes]. The body is read as a stream and the
/// read stops at the cap, so a server cannot make the app buffer more than
/// that, whatever length it declares.
Future<String?> readBoundedBody(
  Client client,
  Uri url, {
  int maxBytes = 64 * 1024,
}) => readBoundedResponse(client, Request('GET', url), maxBytes: maxBytes);

/// Sends [request] and reads the answer like [readBoundedBody].
Future<String?> readBoundedResponse(
  Client client,
  BaseRequest request, {
  int maxBytes = 64 * 1024,
}) async {
  final response = await client.send(request);
  if (response.statusCode < 200 || response.statusCode >= 300) return null;
  final declared = response.contentLength;
  if (declared != null && declared > maxBytes) return null;
  final body = BytesBuilder(copy: false);
  await for (final chunk in response.stream) {
    body.add(chunk);
    if (body.length > maxBytes) return null;
  }
  return utf8.decode(body.takeBytes(), allowMalformed: true);
}
