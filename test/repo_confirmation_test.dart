// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/sign_in/view_model/sign_in_view_model.dart';
import 'package:odango/utils/branding/repo_links.dart';
import 'package:odango/utils/error_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The repository default of this build is only assumed to belong to the
/// owner. Until the owner confirms it, nothing is fetched from it on its own.
void main() {
  final requests = <Uri>[];
  final client = MockClient((request) async {
    requests.add(request.url);
    return http.Response(
      jsonEncode({
        'public_servers': [
          {'name': 'listed.example.org', 'reg_method': 'open'},
        ],
        'items': [
          {'html_url': 'https://github.com/swovo/odango/issues/7'},
        ],
      }),
      200,
    );
  });

  setUp(() async {
    requests.clear();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.reset(loadWebConfigFile: false);
  });

  group('the setting', () {
    test('is off by default', () {
      expect(AppSettings.repositoryConfirmed.defaultValue, isFalse);
      expect(AppSettings.repositoryConfirmed.value, isFalse);
      expect(RepoLinks.confirmed(), isNull);
    });

    test('turns the repository on for automatic requests', () async {
      await AppSettings.repositoryConfirmed.setItem(true);
      expect(RepoLinks.confirmed()?.owner, 'swovo');
      await AppSettings.repositoryUrl.setItem('https://github.com/acme/chat');
      expect(RepoLinks.confirmed()?.owner, 'acme');
    });

    test('does not make an invalid repository valid', () async {
      await AppSettings.repositoryConfirmed.setItem(true);
      await AppSettings.repositoryUrl.setItem('http://evil.example/a/b');
      expect(RepoLinks.confirmed(), isNull);
    });

    test('links the user opens by hand still work while it is off', () {
      expect(RepoLinks.configured.page.toString(), startsWith('https://'));
    });
  });

  group('the recommended homeserver list', () {
    test('is not requested while the repository is unconfirmed', () async {
      expect(
        await fetchPublicHomeservers(client, RepoLinks.confirmed()),
        isNull,
      );
      expect(requests, isEmpty);
    });

    test('is requested from the confirmed repository only', () async {
      await AppSettings.repositoryConfirmed.setItem(true);
      final list = await fetchPublicHomeservers(client, RepoLinks.confirmed());
      expect(list?.map((server) => server.name), ['listed.example.org']);
      expect(
        requests.single.toString(),
        startsWith('https://raw.githubusercontent.com/swovo/odango/'),
      );
    });
  });

  group('issue search', () {
    test('makes no request while the repository is unconfirmed', () async {
      expect(await findExistingIssue('abc', client: client), isNull);
      expect(requests, isEmpty);
    });

    test('searches the confirmed repository', () async {
      await AppSettings.repositoryConfirmed.setItem(true);
      expect(await findExistingIssue('abc', client: client), isNotNull);
      expect(requests, hasLength(1));
    });
  });

  test('no automatic request is derived from the unconfirmed default', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File ||
          !entity.path.endsWith('.dart') ||
          entity.path == 'lib/utils/branding/repo_links.dart') {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(
          r'RepoLinks\.fromSettings\(\)|'
          r'RepoLinks\.configured\.(homeserverList|latestReleaseApi|searchIssues)',
        ).hasMatch(lines[i])) {
          hits.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('every automatic request asks for the confirmed repository only', () {
    for (final path in [
      'lib/pages/sign_in/view_model/sign_in_view_model.dart',
      'lib/utils/error_reporter.dart',
      'lib/utils/show_update_snackbar.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('RepoLinks.confirmed()'), reason: path);
      expect(source, isNot(contains('RepoLinks.fromSettings')), reason: path);
    }
    expect(
      File(
        'lib/pages/sign_in/view_model/sign_in_view_model.dart',
      ).readAsStringSync(),
      isNot(contains('RepoLinks.configured')),
    );
  });

  test('the privacy notice lists both GitHub requests and the condition', () {
    final privacy = File('PRIVACY.md').readAsStringSync();
    expect(privacy, contains('raw.githubusercontent.com'));
    expect(privacy, contains('api.github.com/search/issues'));
    expect(privacy, contains('repositoryConfirmed'));
  });

  test('the web config may confirm the repository', () {
    expect(
      filterPlatformConfiguration({
        'repositoryConfirmed': true,
      }, PlatformConfigSource.web),
      {'repositoryConfirmed': true},
    );
  });
}
