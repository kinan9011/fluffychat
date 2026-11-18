// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:http/http.dart';
import 'package:matrix/fake_matrix_api.dart';

class RecordedRequest {
  const RecordedRequest(this.method, this.url, this.body);

  final String method;
  final Uri url;
  final String body;

  String get path => Uri.decodeFull(url.path);

  Object? get json {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => '$method ${url.path}?${url.query}';
}

/// The fake server, plus a log of every request that left the client. Network
/// layer privacy tests assert on this log: a request that was never made
/// cannot leak anything.
class RecordingApi extends FakeMatrixApi {
  final log = <RecordedRequest>[];
  var _counter = 0;

  /// The answer to `GET .../threads` (null: the fake server's own answer).
  Object? threadsResponse;

  /// The next write to `/send/` is refused with a server error.
  bool failNextSend = false;

  /// GET paths (by their end) that the server does not know: 404.
  final notFound = <String>{};

  /// Writes to these paths need user-interactive auth: a request without an
  /// `auth` member gets the 401 flow, one with it succeeds.
  final uiaPaths = <String>{};

  /// Runs for every request that leaves the client, before it is answered.
  Future<void> Function(BaseRequest request)? onRequest;

  /// Answers for other GET requests, by the end of their path.
  final getOverrides = <String, Object?>{};

  /// Answers a GET with this JSON when it returns something other than null;
  /// asked first, by the whole url.
  Object? Function(Uri url)? getResponder;

  static final _accept = RegExp(
    r'/receipt/|/read_markers|/typing/|/presence/[^/]+/status|/state/|/send/|/threads|/account_data/',
  );

  void clear() => log.clear();

  List<RecordedRequest> requests(Pattern pathContains, {String? method}) => log
      .where(
        (r) =>
            (method == null || r.method == method) &&
            r.path.contains(pathContains),
      )
      .toList();

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final copy = Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bytes;
    log.add(
      RecordedRequest(
        request.method,
        request.url,
        utf8.decode(bytes, allowMalformed: true),
      ),
    );
    await onRequest?.call(request);
    if (request.method != 'GET' &&
        uiaPaths.any((path) => request.url.path.contains(path))) {
      final body = copy.body.isEmpty
          ? <String, Object?>{}
          : jsonDecode(copy.body);
      final needsAuth = body is! Map || !body.containsKey('auth');
      return StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode(
              needsAuth
                  ? {
                      'flows': [
                        {
                          'stages': ['m.login.password'],
                        },
                      ],
                      'params': <String, Object?>{},
                      'session': 'uia-session',
                    }
                  : <String, Object?>{},
            ),
          ),
        ),
        needsAuth ? 401 : 200,
        headers: {'content-type': 'application/json'},
      );
    }
    final threads = threadsResponse;
    if (threads != null &&
        request.method == 'GET' &&
        request.url.path.endsWith('/threads')) {
      return StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(threads))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' &&
        notFound.any((end) => request.url.path.endsWith(end))) {
      return StreamedResponse(
        Stream.value(
          utf8.encode(
            '{"errcode":"M_UNRECOGNIZED","error":"Unrecognized request"}',
          ),
        ),
        404,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET') {
      final answer = getResponder?.call(request.url);
      if (answer != null) {
        return StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(answer))),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      for (final entry in getOverrides.entries) {
        if (!request.url.path.endsWith(entry.key)) continue;
        return StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(entry.value))),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
    }
    if (failNextSend &&
        request.method == 'PUT' &&
        request.url.path.contains('/send/')) {
      failNextSend = false;
      return StreamedResponse(
        Stream.value(utf8.encode('{"errcode":"M_FORBIDDEN","error":"nope"}')),
        403,
        headers: {'content-type': 'application/json'},
      );
    }
    final unstubbed =
        request.method != 'GET' && _accept.hasMatch(request.url.path);
    if (!unstubbed) return super.send(copy);
    final response = request.url.path.contains('/send/')
        ? {'event_id': '\$recorded${_counter++}:fakeserver.notexisting'}
        : <String, Object?>{};
    return StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(response))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
