// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odango/utils/branding/repo_links.dart';
import 'package:odango/utils/update_checker.dart';

String _release(
  String tag, {
  String? url,
  String asset = windowsInstallerAssetName,
}) => jsonEncode({
  'tag_name': tag,
  'assets': [
    {
      'name': asset,
      'browser_download_url':
          url ??
          'https://github.com/swovo/odango/releases/download/$tag/$asset',
    },
  ],
});

void main() {
  final repo = RepoLinks.parse('https://github.com/swovo/odango');
  final requests = <Uri>[];

  http.Client client(String body, {int status = 200}) =>
      MockClient((request) async {
        requests.add(request.url);
        return http.Response(body, status);
      });

  setUp(requests.clear);

  test('asks the latest release of the configured repository only', () async {
    final update = await checkForUpdate(
      client: client(_release('v2.0.0')),
      repo: repo,
      currentVersion: '1.0.0',
    );
    expect(requests.map((uri) => uri.toString()), [
      'https://api.github.com/repos/swovo/odango/releases/latest',
    ]);
    expect(update?.version, '2.0.0');
    expect(
      update?.downloadUrl,
      'https://github.com/swovo/odango/releases/download/v2.0.0/odango-windows-x64-setup.exe',
    );
  });

  test('a repository that is not valid makes no request at all', () async {
    final update = await checkForUpdate(
      client: client(_release('v2.0.0')),
      repo: RepoLinks.parse('http://evil.example/swovo/odango'),
      currentVersion: '1.0.0',
    );
    expect(update, isNull);
    expect(requests, isEmpty);
  });

  test('the same version is no update', () async {
    expect(
      await checkForUpdate(
        client: client(_release('v1.0.0')),
        repo: repo,
        currentVersion: '1.0.0',
      ),
      isNull,
    );
  });

  test('only the Odango installer counts, not the upstream one', () async {
    expect(windowsInstallerAssetName, 'odango-windows-x64-setup.exe');
    expect(
      await checkForUpdate(
        client: client(
          _release('v2.0.0', asset: 'fluffychat-windows-x64-setup.exe'),
        ),
        repo: repo,
        currentVersion: '1.0.0',
      ),
      isNull,
    );
  });

  test('a download link that leaves the repository is refused', () async {
    for (final url in [
      'https://evil.example/swovo/odango/releases/download/v2/x.exe',
      'http://github.com/swovo/odango/releases/download/v2/x.exe',
      'https://github.com/other/repo/releases/download/v2/x.exe',
      'https://github.com/swovo/odango/raw/main/x.exe',
      'javascript:alert(1)',
    ]) {
      expect(
        await checkForUpdate(
          client: client(_release('v2.0.0', url: url)),
          repo: repo,
          currentVersion: '1.0.0',
        ),
        isNull,
        reason: url,
      );
    }
  });

  test('errors and garbage answers are no update', () async {
    expect(
      await checkForUpdate(
        client: client('', status: 404),
        repo: repo,
        currentVersion: '1',
      ),
      isNull,
    );
    expect(
      await checkForUpdate(
        client: client('not json'),
        repo: repo,
        currentVersion: '1',
      ),
      isNull,
    );
    expect(
      await checkForUpdate(
        client: client('{"tag_name": 5}'),
        repo: repo,
        currentVersion: '1',
      ),
      isNull,
    );
  });

  group('versions are compared, not just different', () {
    Future<String?> latest(String tag, String current) async =>
        (await checkForUpdate(
          client: client(_release(tag)),
          repo: repo,
          currentVersion: current,
        ))?.version;

    test('an older release is no update', () async {
      expect(await latest('v1.9.0', '2.0.0'), isNull);
      expect(await latest('v1.2.3', '1.2.4'), isNull);
      expect(await latest('v2.0.0', '2.0.1'), isNull);
    });

    test('a newer release is an update, numerically', () async {
      expect(await latest('v1.10.0', '1.9.0'), '1.10.0');
      expect(await latest('v2.0.0', '1.99.99'), '2.0.0');
      expect(await latest('v1.2.4', '1.2.3'), '1.2.4');
    });

    test('a build number or the same version is no update', () async {
      expect(await latest('v1.2.3', '1.2.3+45'), isNull);
      expect(await latest('v1.2.3', '1.2.3'), isNull);
      expect(await latest('v1.2.4', '1.2.3+45'), '1.2.4');
    });

    test('versions that are not numbers are no update', () async {
      expect(await latest('nightly', '1.0.0'), isNull);
      expect(await latest('v2.0.0', 'dev'), isNull);
    });
  });
}
