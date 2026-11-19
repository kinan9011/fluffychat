// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/utils/branding/repo_links.dart';

void main() {
  group('RepoLinks.parse', () {
    test('accepts a GitHub https repository', () {
      for (final url in [
        'https://github.com/kinan9011/odango',
        'https://github.com/kinan9011/odango/',
        'https://github.com/kinan9011/odango.git',
        'https://github.com/a-b/c_d.e',
      ]) {
        final links = RepoLinks.parse(url);
        expect(links, isNotNull, reason: url);
      }
      final links = RepoLinks.parse('https://github.com/kinan9011/odango.git')!;
      expect(links.owner, 'kinan9011');
      expect(links.name, 'odango');
    });

    test('rejects everything that is not a plain GitHub https repository', () {
      for (final url in [
        '',
        'http://github.com/kinan9011/odango',
        'git@github.com:kinan9011/odango.git',
        'ssh://github.com/kinan9011/odango',
        'https://github.com/swovo',
        'https://github.com/kinan9011/odango/issues',
        'https://github.com/kinan9011/odango/tree/main',
        'https://evil.example/kinan9011/odango',
        'https://github.com.evil.example/kinan9011/odango',
        'https://user@github.com/kinan9011/odango',
        'https://user:pw@github.com/kinan9011/odango',
        'https://github.com:444/kinan9011/odango',
        'https://github.com/kinan9011/odango?x=1',
        'https://github.com/kinan9011/odango#frag',
        'https://github.com/../odango',
        'https://github.com/swovo/..',
        'https://github.com/swo vo/odango',
        'https://github.com/kinan9011/odango%2Fevil',
        'javascript:alert(1)',
        'https://GITHUB.com/kinan9011/odango/extra/segment',
      ]) {
        expect(RepoLinks.parse(url), isNull, reason: url);
      }
    });

    test('rejects over-long owner and name', () {
      final long = 'a' * 101;
      expect(RepoLinks.parse('https://github.com/$long/odango'), isNull);
      expect(RepoLinks.parse('https://github.com/swovo/$long'), isNull);
    });
  });

  group('derived addresses', () {
    final links = RepoLinks.parse('https://github.com/kinan9011/odango')!;

    test('point at the repository and nowhere else', () {
      expect(links.page.toString(), 'https://github.com/kinan9011/odango');
      expect(
        links.issues.toString(),
        'https://github.com/kinan9011/odango/issues',
      );
      expect(
        links.newIssue.toString(),
        'https://github.com/kinan9011/odango/issues/new',
      );
      expect(
        links.releases.toString(),
        'https://github.com/kinan9011/odango/releases',
      );
      expect(
        links.latestReleaseApi.toString(),
        'https://api.github.com/repos/kinan9011/odango/releases/latest',
      );
      expect(
        links.homeserverList.toString(),
        'https://raw.githubusercontent.com/kinan9011/odango/refs/heads/main/recommended_homeservers.json',
      );
      expect(
        links.searchIssues('abc123').toString(),
        'https://api.github.com/search/issues?q=repo:kinan9011/odango+is:issue+abc123',
      );
    });

    test('the issue search hash cannot add query terms', () {
      final uri = links.searchIssues('x&per_page=100 label:foo');
      expect(uri.host, 'api.github.com');
      expect(uri.queryParameters.keys, ['q']);
      expect(uri.query, isNot(contains('&')));
      expect(uri.query, isNot(contains(' ')));
    });
  });

  test('the default repository is the Odango repository', () {
    expect(RepoLinks.defaultRepo.owner, 'kinan9011');
    expect(RepoLinks.defaultRepo.name, 'odango');
  });
}
