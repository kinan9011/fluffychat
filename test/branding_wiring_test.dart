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
import 'package:odango/utils/error_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _source(String path) => File(path).readAsStringSync();

List<File> _libFiles() => [
  for (final entity in Directory('lib').listSync(recursive: true))
    if (entity is File &&
        entity.path.endsWith('.dart') &&
        !entity.path.startsWith('lib/l10n/'))
      entity,
];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.reset(loadWebConfigFile: false);
  });

  group('crash reports', () {
    test('nothing in the app names an upstream crash host', () {
      final hits = [
        for (final file in _libFiles())
          if (RegExp(
            r'crash\.fluffy|\bsentry\b|sentry\.io',
            caseSensitive: false,
          ).hasMatch(file.readAsStringSync()))
            file.path,
      ];
      expect(hits, isEmpty);
    });

    test('automatic reports are off until the user turns them on', () {
      expect(AppSettings.autoSendErrorReports.defaultValue, isNull);
      expect(AppSettings.autoSendErrorReports.value, isNull);
    });

    test('the declared default stays null (nullable defaults read as null)', () {
      expect(
        _source('lib/config/setting_keys.dart'),
        contains(
          "autoSendErrorReports<bool?>('com.swovo.odango.auto_send_eror_reports', null)",
        ),
      );
    });

    test('the issue search follows the repository setting', () async {
      await AppSettings.repositoryConfirmed.setItem(true);
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({
            'items': [
              {'html_url': 'https://github.com/kinan9011/odango/issues/7'},
            ],
          }),
          200,
        );
      });
      final found = await findExistingIssue('abc', client: client);
      expect(found.toString(), 'https://github.com/kinan9011/odango/issues/7');
      expect(
        requests.single.toString(),
        startsWith(
          'https://api.github.com/search/issues?q=repo:kinan9011/odango+',
        ),
      );

      await AppSettings.repositoryUrl.setItem('https://github.com/acme/chat');
      requests.clear();
      await findExistingIssue('abc', client: client);
      expect(requests.single.toString(), contains('repo:acme/chat'));
    });

    test('without a valid repository nothing is requested', () async {
      await AppSettings.repositoryConfirmed.setItem(true);
      await AppSettings.repositoryUrl.setItem('http://evil.example/a/b');
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response('{}', 200);
      });
      expect(await findExistingIssue('abc', client: client), isNull);
      expect(requests, isEmpty);
    });
  });

  group('push', () {
    test('the FCM path needs a resolved gateway before it registers', () {
      final source = _source('lib/utils/background_push.dart');
      final resolve = source.indexOf('resolvePushGateway(');
      final register = source.indexOf(
        'await setupPusher(client: client, gatewayUrl: gatewayUrl',
      );
      expect(resolve, greaterThan(0));
      expect(register, greaterThan(resolve));
      final between = source.substring(resolve, register);
      expect(between, contains('if (gatewayUrl == null)'));
      expect(between, contains('_noGatewayWarning()'));
      expect(between, contains('return;'));
    });

    test(
      'setupPusher returns before any pusher is written without gateway',
      () {
        final source = _source('lib/utils/background_push.dart');
        final start = source.indexOf('Future<void> setupPusher(');
        final guard = source.indexOf(
          'gatewayUrl == null || token == null',
          start,
        );
        final delete = source.indexOf('deletePusher(', start);
        final post = source.indexOf('postPusher(', start);
        expect(guard, greaterThan(start));
        expect(delete, greaterThan(guard));
        expect(post, greaterThan(guard));
      },
    );

    test('no upstream gateway host remains anywhere in the app', () {
      for (final file in _libFiles()) {
        expect(
          file.readAsStringSync(),
          isNot(
            contains(
              'push.fluffy'
              'chat',
            ),
          ),
        );
      }
    });
  });

  group('support entry points open the dialog, not a link', () {
    test('the overflow menu entry', () {
      final source = _source('lib/pages/chat_list/client_chooser_button.dart');
      final start = source.indexOf('case SettingsAction.support:');
      expect(start, greaterThan(0));
      final entry = source.substring(start, source.indexOf('break;', start));
      expect(entry, contains('showSupportDialog(context)'));
      expect(entry, isNot(contains('launchWebUrl')));
      expect(source, contains('supportOdango'));
    });

    test('the update check obeys the setting and the repository setting', () {
      final source = _source('lib/utils/show_update_snackbar.dart');
      expect(
        source,
        contains(
          'if (!PlatformInfos.isWindows || !AppSettings.checkForUpdates.value)',
        ),
      );
      expect(source, contains('repo: RepoLinks.confirmed()'));
      expect(source, isNot(contains('RepoLinks.configured,')));
    });

    test('the update dialog', () {
      final source = _source('lib/utils/show_update_snackbar.dart');
      expect(source, contains('showSupportDialog(context)'));
      expect(source, isNot(contains('ko-fi')));
    });

    test('no donation page of the upstream author is linked as support', () {
      final hits = [
        for (final file in _libFiles())
          if (file.readAsStringSync().contains('ko-fi.com')) file.path,
      ];
      expect(hits, isEmpty);
    });
  });
}
