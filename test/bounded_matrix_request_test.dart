// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:fluffychat/utils/bounded_matrix_request.dart';
import 'package:fluffychat/utils/search/public_directory.dart';
import 'package:fluffychat/utils/search/search_filter.dart';
import 'package:fluffychat/utils/search/search_query.dart';
import 'package:fluffychat/utils/search/server_search.dart';
import 'package:fluffychat/utils/spaces/space_hierarchy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show BaseRequest, StreamedResponse;
import 'package:matrix/matrix.dart';

import 'utils/recording_api.dart';
import 'utils/search_fixtures.dart';
import 'utils/test_client.dart';

/// Answers the three relayed endpoints with whatever the test sets, and
/// everything else like the fake server.
class _Hostile extends RecordingApi {
  Stream<List<int>>? body;
  int? declared;
  int status = 200;
  var chunksRead = 0;
  final auth = <String?>[];

  bool _hostile(BaseRequest request) =>
      body != null &&
      (request.url.path.endsWith('/hierarchy') ||
          request.url.path.endsWith('/search') ||
          request.url.path.endsWith('/publicRooms'));

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    if (!_hostile(request)) return super.send(request);
    final bytes = await request.finalize().toBytes();
    auth.add(request.headers['authorization']);
    log.add(RecordedRequest(request.method, request.url, utf8.decode(bytes)));
    return StreamedResponse(
      body!.map((chunk) {
        chunksRead++;
        return chunk;
      }),
      status,
      contentLength: declared,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  late Client client;
  final api = _Hostile();

  setUpAll(() async {
    client = await prepareTestClient(loggedIn: true, httpClient: api);
  });
  tearDownAll(() => client.dispose(closeDatabase: true));
  setUp(() {
    api.body = null;
    api.declared = null;
    api.status = 200;
    api.chunksRead = 0;
    api.auth.clear();
    api.clear();
  });

  Stream<List<int>> endless() =>
      Stream.periodic(Duration.zero, (_) => List.filled(64 * 1024, 0x61));

  Stream<List<int>> small(Object json) =>
      Stream.value(utf8.encode(jsonEncode(json)));

  group('the helper', () {
    test(
      'a small answer is returned and the request carries the token',
      () async {
        api.body = small({'a': 1});
        final json = await boundedMatrixJson(
          client,
          'POST',
          '_matrix/client/v3/search',
          maxBytes: 100,
          query: {'next_batch': 'abc'},
          body: {'x': 1},
        );
        expect(json, {'a': 1});
        expect(api.auth.single, 'Bearer ${client.accessToken}');
        final sent = api.log.single;
        expect(sent.method, 'POST');
        expect(sent.url.queryParameters, {'next_batch': 'abc'});
        expect(sent.json, {'x': 1});
      },
    );

    test('an answer over the cap is refused, declared or not', () async {
      api.body = small({'a': 'x' * 200});
      api.declared = 300;
      await expectLater(
        boundedMatrixJson(client, 'GET', '_matrix/x/search', maxBytes: 100),
        throwsA(isA<FormatException>()),
      );
      api.declared = null;
      await expectLater(
        boundedMatrixJson(client, 'GET', '_matrix/x/search', maxBytes: 100),
        throwsA(isA<FormatException>()),
      );
    });

    test('an answer that is no object or no success throws', () async {
      api.body = small([1, 2]);
      await expectLater(
        boundedMatrixJson(client, 'GET', '_matrix/x/search', maxBytes: 100),
        throwsA(isA<FormatException>()),
      );
      api.body = small({'a': 1});
      api.status = 500;
      await expectLater(
        boundedMatrixJson(client, 'GET', '_matrix/x/search', maxBytes: 100),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('hostile oversize answers', () {
    test('/hierarchy that never ends stops at the cap', () async {
      api.body = endless();
      await expectLater(
        fetchHierarchyPage(client, '!space:example.org'),
        throwsA(isA<FormatException>()),
      );
      expect(
        api.chunksRead * 64 * 1024,
        lessThan(maxHierarchyBytes + 2 * 64 * 1024),
      );
    });

    test('/hierarchy asks with max_depth 1 and an escaped room id', () async {
      api.body = small({'rooms': <Object?>[]});
      await fetchHierarchyPage(client, '!sp ace:example.org', from: 'tok');
      final sent = api.log.single;
      expect(sent.path, contains('/rooms/!sp ace:example.org/hierarchy'));
      expect(sent.url.queryParameters['max_depth'], '1');
      expect(sent.url.queryParameters['from'], 'tok');
    });

    test('/search that never ends stops at the cap', () async {
      api.body = endless();
      final room = searchRoom(client, '!open:example.org', encrypted: false);
      client.rooms
        ..clear()
        ..add(room);
      await expectLater(
        ServerSearch(
          client,
        ).search(SearchQuery.parse('needle'), MessageSearchFilter.none),
        throwsA(isA<FormatException>()),
      );
      expect(
        api.chunksRead * 64 * 1024,
        lessThan(ServerSearch.maxResponseBytes + 2 * 64 * 1024),
      );
    });

    test('/publicRooms that never ends stops at the cap', () async {
      api.body = endless();
      await expectLater(
        queryPublicDirectory(client, term: 'abc'),
        throwsA(isA<FormatException>()),
      );
      expect(
        api.chunksRead * 64 * 1024,
        lessThan(maxDirectoryBytes + 2 * 64 * 1024),
      );
    });

    test(
      '/publicRooms sends the word, the server and the page token',
      () async {
        api.body = small({'chunk': <Object?>[]});
        await queryPublicDirectory(
          client,
          server: 'other.example',
          term: 'abc',
          since: 'p1',
        );
        final sent = api.log.single;
        expect(sent.url.queryParameters['server'], 'other.example');
        expect(sent.json, {
          'filter': {'generic_search_term': 'abc'},
          'limit': 20,
          'since': 'p1',
        });
      },
    );
  });
}
