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
        'https://github.com/swovo/odango',
        'https://github.com/swovo/odango/',
        'https://github.com/swovo/odango.git',
        'https://github.com/a-b/c_d.e',
      ]) {
        final links = RepoLinks.parse(url);
        expect(links, isNotNull, reason: url);
      }
      final links = RepoLinks.parse('https://github.com/swovo/odango.git')!;
      expect(links.owner, 'swovo');
      expect(links.name, 'odango');
    });

    test('rejects everything that is not a plain GitHub https repository', () {
      for (final url in [
        '',
        'http://github.com/swovo/odango',
        'git@github.com:swovo/odango.git',
        'ssh://github.com/swovo/odango',
        'https://github.com/swovo',
        'https://github.com/swovo/odango/issues',
        'https://github.com/swovo/odango/tree/main',
        'https://evil.example/swovo/odango',
        'https://github.com.evil.example/swovo/odango',
        'https://user@github.com/swovo/odango',
        'https://user:pw@github.com/swovo/odango',
        'https://github.com:444/swovo/odango',
        'https://github.com/swovo/odango?x=1',
        'https://github.com/swovo/odango#frag',
        'https://github.com/../odango',
        'https://github.com/swovo/..',
        'https://github.com/swo vo/odango',
        'https://github.com/swovo/odango%2Fevil',
        'javascript:alert(1)',
        'https://GITHUB.com/swovo/odango/extra/segment',
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
    final links = RepoLinks.parse('https://github.com/swovo/odango')!;

    test('point at the repository and nowhere else', () {
      expect(links.page.toString(), 'https://github.com/swovo/odango');
      expect(links.issues.toString(), 'https://github.com/swovo/odango/issues');
      expect(
        links.newIssue.toString(),
        'https://github.com/swovo/odango/issues/new',
      );
      expect(
        links.releases.toString(),
        'https://github.com/swovo/odango/releases',
      );
      expect(
        links.latestReleaseApi.toString(),
        'https://api.github.com/repos/swovo/odango/releases/latest',
      );
      expect(
        links.homeserverList.toString(),
        'https://raw.githubusercontent.com/swovo/odango/refs/heads/main/recommended_homeservers.json',
      );
      expect(
        links.searchIssues('abc123').toString(),
        'https://api.github.com/search/issues?q=repo:swovo/odango+is:issue+abc123',
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
    expect(RepoLinks.defaultRepo.owner, 'swovo');
    expect(RepoLinks.defaultRepo.name, 'odango');
  });
}
