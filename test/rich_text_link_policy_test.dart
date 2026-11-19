// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/rich_text/link_policy.dart';

void main() {
  group('LinkPolicy accepts', () {
    const accepted = {
      'https://example.org/a?b=1': 'https://example.org/a?b=1',
      'http://example.org': 'http://example.org',
      'example.org': 'https://example.org',
      'example.org:8080/x': 'https://example.org:8080/x',
      'mailto:a@b.org': 'mailto:a@b.org',
      'matrix:r/room:server.org': 'matrix:r/room:server.org',
      'HTTPS://Example.org': 'https://example.org',
      '  https://example.org  ': 'https://example.org',
    };
    for (final entry in accepted.entries) {
      test(entry.key, () {
        expect(LinkPolicy.parse(entry.key)?.toString(), entry.value);
      });
    }
  });

  group('LinkPolicy rejects', () {
    final rejected = <String>[
      'javascript:alert(1)',
      'JaVaScRiPt:alert(1)',
      'java\tscript:x',
      'java\nscript:x',
      '\u0001javascript:x',
      '  \njavascript:x',
      ' javascript:x',
      'data:text/html,x',
      'DATA:text/html;base64,AAAA',
      'vbscript:x',
      'file:///etc/passwd',
      'intent://x#Intent;end',
      'ftp://x.org',
      'https://bank.com@evil.org',
      'https://',
      'https://exa mple.org',
      'https://a.org/\u202efdp',
      'https://a.org/\u200bx',
      'https://a.org/"onclick=',
      '<https://a.org>',
      '',
      '   ',
      'https://a.org/${'a' * 2049}',
      'mailto:not-an-address',
      'matrix:',
      'https://a%2eorg',
      'https://ex\u0430mple.com',
      'https://evil\u3002com/x',
      'b\u00fccher.de',
      'https://\uff45xample.com',
      'https://xn--e\u0430.com',
      'mailto:support@ex\u0430mple.com',
      'mailto:a@ex%D0%B0mple.com',
      'mailto:a@b\u00fccher.de',
    ];
    for (final input in rejected) {
      test(input.codeUnits.take(24).toList().toString(), () {
        expect(LinkPolicy.parse(input), isNull);
      });
    }
  });

  group('LinkPolicy is deliberate about internationalised hosts', () {
    test('punycode is accepted and shown as written', () {
      expect(
        LinkPolicy.parse('https://xn--bcher-kva.de/x')?.toString(),
        'https://xn--bcher-kva.de/x',
      );
    });

    test('whatever is accepted parses to itself again', () {
      for (final input in [
        'https://example.org/a?b=1#c',
        'example.org:8080/x',
        'HTTPS://Example.org',
        'http://[::1]:8080/x',
        'https://xn--bcher-kva.de',
        'mailto:a@b.org',
        'mailto:a@xn--bcher-kva.de',
        'matrix:r/room:server.org',
        'https://a.b-c_d.org/%41',
      ]) {
        final once = LinkPolicy.parse(input);
        expect(once, isNotNull, reason: input);
        expect(LinkPolicy.parse(once.toString()), once, reason: input);
      }
    });

    test('nothing refused by a first pass is accepted by a second', () {
      for (final input in ['https://ex\u0430mple.com', 'b\u00fccher.de']) {
        expect(LinkPolicy.parse(input), isNull);
        expect(LinkPolicy.parse(Uri.tryParse(input).toString()), isNull);
      }
    });
  });
}
