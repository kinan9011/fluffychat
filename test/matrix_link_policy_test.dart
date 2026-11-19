// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/links/matrix_link_policy.dart';

void main() {
  group('accepted', () {
    final accepted =
        <
          String,
          ({ScannedKind kind, String id, String? event, List<String> via})
        >{
          'https://matrix.to/#/@alice:example.org': (
            kind: ScannedKind.user,
            id: '@alice:example.org',
            event: null,
            via: const [],
          ),
          'https://matrix.to/#/!room:example.org?via=example.org&via=other.example':
              (
                kind: ScannedKind.room,
                id: '!room:example.org',
                event: null,
                via: const ['example.org', 'other.example'],
              ),
          'https://matrix.to/#/%23alias:example.org': (
            kind: ScannedKind.alias,
            id: '#alias:example.org',
            event: null,
            via: const [],
          ),
          'https://matrix.to/#/#alias:example.org': (
            kind: ScannedKind.alias,
            id: '#alias:example.org',
            event: null,
            via: const [],
          ),
          r'https://matrix.to/#/!room:example.org/$event1:example.org': (
            kind: ScannedKind.room,
            id: '!room:example.org',
            event: r'$event1:example.org',
            via: const [],
          ),
          'HTTPS://MATRIX.TO/#/@alice:example.org': (
            kind: ScannedKind.user,
            id: '@alice:example.org',
            event: null,
            via: const [],
          ),
          'matrix:u/alice:example.org': (
            kind: ScannedKind.user,
            id: '@alice:example.org',
            event: null,
            via: const [],
          ),
          'matrix:r/alias:example.org?via=example.org': (
            kind: ScannedKind.alias,
            id: '#alias:example.org',
            event: null,
            via: const ['example.org'],
          ),
          'matrix:roomid/room:example.org': (
            kind: ScannedKind.room,
            id: '!room:example.org',
            event: null,
            via: const [],
          ),
          r'matrix:roomid/room:example.org/e/event1:example.org': (
            kind: ScannedKind.room,
            id: '!room:example.org',
            event: r'$event1:example.org',
            via: const [],
          ),
          'com.swovo.odango://chat/@alice:example.org': (
            kind: ScannedKind.user,
            id: '@alice:example.org',
            event: null,
            via: const [],
          ),
        };
    for (final entry in accepted.entries) {
      test(entry.key, () {
        final target = MatrixLinkPolicy.parse(entry.key)!;
        expect(target.kind, entry.value.kind);
        expect(target.identifier, entry.value.id);
        expect(target.eventId, entry.value.event);
        expect(target.via, entry.value.via);
      });
    }

    test('surrounding whitespace is ignored', () {
      expect(
        MatrixLinkPolicy.parse('  https://matrix.to/#/@a:b.c\n'),
        isNotNull,
      );
    });

    test('version 12 room ids without a server part', () {
      final id = '!${'a' * 43}';
      expect(MatrixLinkPolicy.parse('https://matrix.to/#/$id')?.identifier, id);
    });

    test('a user id with a port', () {
      expect(
        MatrixLinkPolicy.parse(
          'https://matrix.to/#/@a:example.org:8448',
        )?.identifier,
        '@a:example.org:8448',
      );
    });
  });

  group('rejected', () {
    final rejected = <String, String>{
      'empty': '',
      'blank': '   ',
      'javascript': 'javascript:alert(1)',
      'data': 'data:text/html;base64,PHNjcmlwdD4=',
      'intent': 'intent://scan/#Intent;scheme=zxing;end',
      'file': 'file:///etc/passwd',
      'plain text': 'hello world',
      'a phone number': 'tel:+4912345',
      'mailto': 'mailto:a@example.org',
      'other https host': 'https://evil.example/#/@alice:example.org',
      'lookalike suffix': 'https://matrix.to.evil.example/#/@alice:example.org',
      'lookalike prefix': 'https://evilmatrix.to/#/@alice:example.org',
      'plain http': 'http://matrix.to/#/@alice:example.org',
      'user info': 'https://matrix.to@evil.example/#/@alice:example.org',
      'user info and password':
          'https://matrix.to:pw@evil.example/#/@alice:example.org',
      'a port': 'https://matrix.to:8443/#/@alice:example.org',
      'a path': 'https://matrix.to/evil/#/@alice:example.org',
      'a query before the fragment':
          'https://matrix.to/?x=1#/@alice:example.org',
      'no fragment': 'https://matrix.to/@alice:example.org',
      'a homograph host': 'https://matrix.tо/#/@alice:example.org',
      'a homograph identifier': 'https://matrix.to/#/@аlice:example.org',
      'a bidi override': 'https://matrix.to/#/@ali\u202Ece:example.org',
      'a zero width space': 'https://matrix.to/#/@ali\u200Bce:example.org',
      'a control character': 'https://matrix.to/#/@ali\u0000ce:example.org',
      'a newline':
          'https://matrix.to/#/@alice:example.org\nhttps://evil.example',
      'a space inside': 'https://matrix.to/#/@ali ce:example.org',
      'a user without a server': 'https://matrix.to/#/@alice',
      'a user with an invalid server':
          'https://matrix.to/#/@alice:exa mple.org',
      'a user with a path as server':
          'https://matrix.to/#/@alice:evil.example/path',
      'an ipv6 server': 'https://matrix.to/#/@alice:[::1]',
      'an event on a user':
          r'https://matrix.to/#/@alice:example.org/$event:example.org',
      'a bad event id': 'https://matrix.to/#/!room:example.org/notanevent',
      'three segments':
          r'https://matrix.to/#/!room:example.org/$e:example.org/extra',
      'an empty segment': 'https://matrix.to/#//@alice:example.org',
      'a bad percent escape': 'https://matrix.to/#/%zz@alice:example.org',
      'a room id without a body': 'https://matrix.to/#/!',
      'a room id with a query inside': 'https://matrix.to/#/!a%3Fb:example.org',
      'a room id with a fragment inside':
          'https://matrix.to/#/!a%23b:example.org',
      'a room id with a slash in the local part':
          'https://matrix.to/#/!a%2Fb:example.org',
      'a room id with a bidi override':
          'https://matrix.to/#/!a%E2%80%AEb:example.org',
      'a room id with a zero width space':
          'https://matrix.to/#/!a%E2%80%8Bb:example.org',
      'a room id with an invalid server':
          'https://matrix.to/#/!room:exa%20mple.org',
      'a room id with a path as server':
          'https://matrix.to/#/!room:evil.example%2Fx',
      'an unknown sigil': 'https://matrix.to/#/%2Balice:example.org',
      'a matrix uri with a fragment': 'matrix:u/alice:example.org#evil',
      'an unknown matrix uri kind': 'matrix:x/alice:example.org',
      'a matrix uri with too few parts': 'matrix:u',
      'a matrix uri event without e':
          r'matrix:roomid/room:example.org/x/event:example.org',
      'a matrix uri event on a user':
          r'matrix:u/alice:example.org/e/event:example.org',
      'a deep link of another app': 'evil.app://chat/@alice:example.org',
      'over the length cap': 'https://matrix.to/#/@${'a' * 2100}:example.org',
    };
    for (final entry in rejected.entries) {
      test(entry.key, () {
        expect(MatrixLinkPolicy.parse(entry.value), isNull);
      });
    }

    test('a long but otherwise valid link is over the length cap', () {
      final query = List.filled(300, 'via=a.example').join('&');
      final link = 'https://matrix.to/#/@alice:example.org?$query';
      expect(link.length, greaterThan(MatrixLinkPolicy.maxLength));
      expect(MatrixLinkPolicy.parse(link), isNull);
      expect(
        MatrixLinkPolicy.parse(
          'https://matrix.to/#/@alice:example.org?via=a.example',
        ),
        isNotNull,
      );
    });

    test('a bidi or zero width character anywhere rejects the whole link', () {
      for (final junk in ['\u202E', '\u200B', '\u0000', '\u2066']) {
        expect(
          MatrixLinkPolicy.parse(
            'https://matrix.to/#/@alice:example.org?via=ok.example$junk',
          ),
          isNull,
          reason: 'end $junk',
        );
      }
      for (final junk in ['\u202E', '\u200B', '\u0000', '\u2066', ' ', '\t']) {
        expect(
          MatrixLinkPolicy.parse(
            'https://matrix.to/#/@alice:example.org?utm=a${junk}b',
          ),
          isNull,
          reason: 'middle $junk',
        );
      }
    });

    test('user info on the real host is rejected', () {
      expect(
        MatrixLinkPolicy.parse(
          'https://user:pw@matrix.to/#/@alice:example.org',
        ),
        isNull,
      );
      expect(
        MatrixLinkPolicy.parse('https://user@matrix.to/#/@alice:example.org'),
        isNull,
      );
    });

    test('a user id that is too long', () {
      expect(
        MatrixLinkPolicy.parse('https://matrix.to/#/@${'a' * 300}:example.org'),
        isNull,
      );
    });
  });

  group('normalizedUrl', () {
    test('is rebuilt from the parts, never the scanned text', () {
      final target = MatrixLinkPolicy.parse(
        'HTTPS://Matrix.To/#/%40alice%3Aexample.org?via=example.org&evil=1',
      )!;
      expect(
        target.normalizedUrl,
        'https://matrix.to/#/@alice:example.org?via=example.org',
      );
    });

    test('keeps the event id', () {
      final target = MatrixLinkPolicy.parse(
        r'matrix:roomid/room:example.org/e/ev:example.org?via=a.example',
      )!;
      expect(
        target.normalizedUrl,
        r'https://matrix.to/#/!room:example.org/$ev:example.org?via=a.example',
      );
    });

    test('contains nothing of the junk that was rejected', () {
      final target = MatrixLinkPolicy.parse(
        'https://matrix.to/#/!room:example.org?via=evil.example/path&via=user@evil.example&via=ok.example',
      )!;
      expect(target.normalizedUrl, contains('via=ok.example'));
      expect(target.normalizedUrl, isNot(contains('evil')));
    });
  });

  group('via', () {
    test('a hundred servers are cut at five', () {
      final query = [for (var n = 0; n < 100; n++) 'via=s$n.example'].join('&');
      final target = MatrixLinkPolicy.parse(
        'https://matrix.to/#/!r:example.org?$query',
      )!;
      expect(target.via.length, MatrixLinkPolicy.maxVia);
      expect(target.via.first, 's0.example');
    });

    test('invalid names are dropped', () {
      for (final bad in [
        'evil.example/path',
        'user@evil.example',
        '[::1]',
        'a b',
        '',
        '-bad.example',
        'bad-.example',
        'a..b',
        '${'a' * 70}.example',
        'x' * 300,
        'host:99999999',
        'host:port',
        'host:70000',
      ]) {
        expect(MatrixLinkPolicy.isServerName(bad), isFalse, reason: bad);
      }
      for (final good in [
        'example.org',
        'a-b.example',
        'example.org:8448',
        '1.2.3.4',
        'localhost',
      ]) {
        expect(MatrixLinkPolicy.isServerName(good), isTrue, reason: good);
      }
    });

    test('safeVia dedupes, keeps the order and ignores other types', () {
      expect(
        MatrixLinkPolicy.safeVia([
          'a.example',
          5,
          null,
          'b.example',
          'a.example',
          'bad host',
        ]),
        ['a.example', 'b.example'],
      );
    });

    test('safeVia of a huge list ends quickly', () {
      final stopwatch = Stopwatch()..start();
      MatrixLinkPolicy.safeVia(List.filled(1000000, 'x y'));
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('links are built with escaped identifiers', () {
    test('a user id with a slash is shown and opened as the same id', () {
      final target = MatrixLinkPolicy.parse(
        'https://matrix.to/#/%40a%2Fb:example.org',
      )!;
      expect(target.identifier, '@a/b:example.org');
      final url = target.normalizedUrl;
      expect(url, isNot(contains('a/b')));
      final again = MatrixLinkPolicy.parse(url)!;
      expect(again.identifier, target.identifier);
      expect(again.kind, ScannedKind.user);
    });

    test('an event id with slashes and plus signs survives', () {
      final target = MatrixLinkPolicy.parse(
        'https://matrix.to/#/!room:example.org/%24ab%2Fcd%2B%3D%3D',
      )!;
      expect(target.eventId, r'$ab/cd+==');
      final again = MatrixLinkPolicy.parse(target.normalizedUrl)!;
      expect(again.eventId, target.eventId);
      expect(again.identifier, target.identifier);
    });

    test('a link to an alias keeps its sigil and has no stray parameters', () {
      final link = MatrixLinkPolicy.link(
        '#a/b:example.org',
        via: ['example.org'],
      );
      expect(link, startsWith('https://matrix.to/#/#a'));
      expect(link, endsWith('?via=example.org'));
      expect('?'.allMatches(link), hasLength(1));
      expect(MatrixLinkPolicy.parse(link)!.identifier, '#a/b:example.org');
    });

    test('the invite link of a space uses a valid alias, else the room id', () {
      expect(
        MatrixLinkPolicy.inviteLink(
          alias: '#makers:example.org',
          roomId: '!space:example.org',
          via: 'example.org',
        ),
        'https://matrix.to/#/#makers:example.org?via=example.org',
      );
      for (final hostile in [
        '#a?via=evil.example:example.org',
        '#a&via=evil.example:example.org',
        '#a#b:example.org',
        '#a b:example.org',
        '',
      ]) {
        final link = MatrixLinkPolicy.inviteLink(
          alias: hostile,
          roomId: '!space:example.org',
          via: 'example.org',
        );
        expect(
          link,
          'https://matrix.to/#/!space:example.org?via=example.org',
          reason: hostile,
        );
        expect(link, isNot(contains('evil')));
      }
    });

    test('no invite link without a valid server', () {
      expect(
        MatrixLinkPolicy.inviteLink(
          alias: '',
          roomId: '!space:example.org',
          via: 'bad host',
        ),
        isNull,
      );
      expect(
        MatrixLinkPolicy.inviteLink(
          alias: '',
          roomId: 'junk',
          via: 'a.example',
        ),
        isNull,
      );
    });
  });
}
