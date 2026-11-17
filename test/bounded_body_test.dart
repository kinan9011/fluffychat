// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/bounded_body.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';

class _Server extends BaseClient {
  _Server(this.chunks, {this.contentLength});

  final Stream<List<int>> chunks;
  final int? contentLength;
  int status = 200;

  @override
  Future<StreamedResponse> send(BaseRequest request) async =>
      StreamedResponse(chunks, status, contentLength: contentLength);
}

void main() {
  final url = Uri.parse('https://example.org/x');

  test('a small body is returned as text', () async {
    final client = _Server(Stream.value(utf8.encode('{"a":1}')));
    expect(await readBoundedBody(client, url, maxBytes: 100), '{"a":1}');
  });

  test('a declared length over the cap is refused before any read', () async {
    var read = false;
    final client = _Server(
      Stream.fromFuture(
        Future(() {
          read = true;
          return [1];
        }),
      ),
      contentLength: 1000,
    );
    expect(await readBoundedBody(client, url, maxBytes: 100), isNull);
    expect(read, isFalse);
  });

  test('a stream that lies about its length stops at the cap', () async {
    var chunks = 0;
    final endless = Stream<List<int>>.periodic(Duration.zero, (_) {
      chunks++;
      return List.filled(40, 0x61);
    });
    final client = _Server(endless);
    expect(await readBoundedBody(client, url, maxBytes: 100), isNull);
    expect(chunks, lessThan(10));
  });

  test('a body of exactly the cap is accepted', () async {
    final client = _Server(Stream.value(List.filled(100, 0x61)));
    expect(await readBoundedBody(client, url, maxBytes: 100), hasLength(100));
  });

  test('an error status gives nothing', () async {
    final client = _Server(Stream.value(utf8.encode('{}')))..status = 404;
    expect(await readBoundedBody(client, url, maxBytes: 100), isNull);
  });
}
