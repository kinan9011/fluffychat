// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present Odango contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/config/app_config.dart';
import 'package:odango/config/setting_keys.dart';

/// Odango is a fork with its own app id. The identifiers of the upstream app
/// must not survive anywhere (a shared id would clash with an installed
/// upstream app: keychain, app group, URL scheme, push app id).
const _excludedRoots = [
  '.claude/',
  'CLAUDE.md',
  'graphify-out/',
  'test/failures/',
  'test/rust/',
  '.planning/',
  'build/',
  '.dart_tool/',
];

const _binaryExtensions = {
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'ico', 'icns', 'ttf', 'otf', 'woff', //
  'woff2', 'apk', 'dex', 'class', 'jar', 'so', 'wasm', 'ogg', 'mp3', 'wav',
  'mp4', 'zip', 'bin', 'dylib', 'a', 'o',
};

List<String> _trackedFiles() {
  final result = Process.runSync('git', [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
  ]);
  if (result.exitCode != 0) throw StateError(result.stderr.toString());
  return [
    for (final path in LineSplitter.split(result.stdout.toString()))
      if (path.isNotEmpty &&
          File(path).existsSync() &&
          !_excludedRoots.any(path.startsWith) &&
          !_binaryExtensions.contains(path.split('.').last.toLowerCase()))
        path,
  ];
}

String? _read(String path) {
  try {
    return utf8.decode(File(path).readAsBytesSync());
  } on FormatException {
    return null;
  }
}

/// Where an upstream identifier may legitimately remain, with the reason.
bool _oldIdAllowed(String path) =>
    path == 'test/odango_rename_guard_test.dart' ||
    path.startsWith('third_party/') ||
    path == 'LICENSE' ||
    path.startsWith('LICENSES/') ||
    (path.startsWith('lib/l10n/intl_') && path != 'lib/l10n/intl_en.arb');

/// Matrix wire names that predate the fork. Other FluffyChat clients read
/// and write them, so they are protocol, not app identity: renaming them
/// would split checkbox state and account data between the two apps.
const _wireNames = {
  'im.fluffychat.checkboxes': 'rel_type of checkbox ticks sent to the room',
  'im.fluffychat.account_bundles': 'account data of the account bundles',
  'im.fluffychat.account_config': 'account data of the account config',
};

/// A third-party dependency version that carries the FluffyChat name (a
/// package published by the upstream project, pinned in pubspec.lock).
const _thirdPartyVersionTag = '+fluffychat.';

/// Header and copyright lines, the only credit allowed in code and platform
/// files.
final _headerCredit = RegExp(
  r'SPDX-FileCopyrightText|Contributors to FluffyChat|FluffyChat authors',
);

/// Credit allowed in documents: the fork notice, the licence/credit lines and
/// the exact upstream repository link.
final _docCredit = RegExp(
  r'SPDX-FileCopyrightText|Contributors to FluffyChat|FluffyChat authors|'
  r'fork of FluffyChat|forked from FluffyChat|built on FluffyChat|'
  r'FluffyChat project|FluffyChat contributors|FluffyChat translators|'
  r'FluffyChat source|FluffyChat history|FluffyChat does|FluffyChat ones|'
  r'FluffyChat logo|FluffyChat is a name|FluffyChat installation|'
  r'FluffyChat or other|data of a FluffyChat|'
  r'https://github\.com/krille-chan/fluffychat',
  caseSensitive: false,
);

/// Dart identifiers that keep the old name: never shown to users and not an
/// identity (renaming them is churn without effect).
final _internalIdentifiers = RegExp(
  r'FluffyThemes|FluffyChatApp|FluffyShare|FluffyChatTester|'
  r'startFluffyChatTest|FluffyChatNotificationActions|'
  r'buildFluffyChatCallKitParams|FluffyChatPushPayload|fluffy_chat_app\.dart|'
  r'fluffy_share\.dart',
);

/// Store texts and the branding flow say in prose that Odango is a fork.
const _storeTextRoots = [
  'android/fastlane/metadata/',
  'ios/fastlane/metadata/',
  'macos/fastlane/metadata/',
  'snap/snapcraft.yaml',
  'integration_test/flows/odango_flows.dart',
];

/// The one place a test asserts the old name is absent.
final _absenceAssertion = RegExp(
  r"find\.textContaining\('FluffyChat'\), findsNothing",
);

/// The upstream repository, linked as credit and nothing else of upstream.
const _upstreamLiterals = {AppConfigUpstream.repo};

abstract class AppConfigUpstream {
  static const repo = 'https://github.com/krille-chan/fluffychat';
}

final _stringLiteral = RegExp(
  r"'(?:[^'\\\n]|\\.)*'"
  r'|"(?:[^"\\\n]|\\.)*"',
);

/// The text a rule applies to. The changelog keeps the FluffyChat history
/// below the Odango section unchanged, so only the Odango section counts.
String? _scanned(String path) {
  final text = _read(path);
  if (text == null || path != 'CHANGELOG.md') return text;
  final history = text.indexOf(RegExp(r'^## v\d', multiLine: true));
  return history < 0 ? text : text.substring(0, history);
}

List<String> _uncreditedLines(String path, Pattern name, RegExp credit) {
  final text = _scanned(path);
  if (text == null) return const [];
  final lines = LineSplitter.split(text).toList();
  return [
    for (var i = 0; i < lines.length; i++)
      if (lines[i]
              .replaceAll(_internalIdentifiers, '')
              .replaceAll(_thirdPartyVersionTag, '')
              .contains(name) &&
          !credit.hasMatch(lines[i]))
        '$path:${i + 1}: ${lines[i].trim()}',
  ];
}

void main() {
  final files = _trackedFiles();

  test('the guard sees the tree', () {
    expect(files.length, greaterThan(500));
    expect(files, contains('lib/config/app_config.dart'));
  });

  group('old identifiers', () {
    final patterns = [
      RegExp(r'chat\.fluffy'),
      RegExp(r'im\.fluffychat'),
      RegExp(r'fluffychat\.im'),
      RegExp(r'fluffy\.chat'),
      RegExp(r'push\.fluffychat'),
    ];

    test('no upstream app id, scheme, key namespace or host is left', () {
      final hits = <String>[];
      for (final path in files) {
        if (_oldIdAllowed(path)) continue;
        final text = _scanned(path);
        if (text == null) continue;
        final lines = LineSplitter.split(text).toList();
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].replaceAll(_thirdPartyVersionTag, '');
          for (final name in _wireNames.keys) {
            line = line.replaceAll(name, '');
          }
          if (patterns.any((pattern) => pattern.hasMatch(line))) {
            hits.add('$path:${i + 1}');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.take(40).join('\n'));
    });

    test('the Dart package is odango', () {
      final hits = [
        for (final path in files)
          if (path.endsWith('.dart') &&
              path != 'test/odango_rename_guard_test.dart' &&
              (_read(path) ?? '').contains('package:fluffychat/'))
            path,
      ];
      expect(hits, isEmpty, reason: hits.take(20).join('\n'));
      expect(_read('pubspec.yaml'), contains('\nname: odango\n'));
    });
  });

  group('visible name', () {
    test('English strings name FluffyChat only where it is credit', () {
      final arb =
          jsonDecode(File('lib/l10n/intl_en.arb').readAsStringSync())
              as Map<String, Object?>;
      const credit = {
        'supportOdangoBody',
        'supportUpstreamSource',
        'aboutBasedOnFluffyChat',
      };
      final hits = [
        for (final MapEntry(:key, :value) in arb.entries)
          if (!key.startsWith('@') &&
              value is String &&
              value.contains(RegExp('fluffy', caseSensitive: false)) &&
              !credit.contains(key))
            '$key: $value',
      ];
      expect(hits, isEmpty, reason: hits.join('\n'));
      expect(arb['applicationName'], isNull);
    });

    test('no Dart string literal in the app names FluffyChat', () {
      final hits = <String>[];
      for (final path in files) {
        if (!path.startsWith('lib/') ||
            !path.endsWith('.dart') ||
            path.startsWith('lib/l10n/')) {
          continue;
        }
        final text = _read(path);
        if (text == null) continue;
        final lines = LineSplitter.split(text).toList();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          for (final match in _stringLiteral.allMatches(line)) {
            final literal = match.group(0)!;
            if (!RegExp('fluffy', caseSensitive: false).hasMatch(literal)) {
              continue;
            }
            final value = literal.substring(1, literal.length - 1);
            if (_upstreamLiterals.contains(value) ||
                _wireNames.containsKey(value)) {
              continue;
            }
            if (line.trimLeft().startsWith('import ') ||
                line.trimLeft().startsWith('export ')) {
              continue;
            }
            hits.add('$path:${i + 1}: $literal');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.take(20).join('\n'));
    });

    test('platform files, store texts and CI carry the Odango name', () {
      const roots = [
        'ios/',
        'macos/',
        'android/',
        'linux/',
        'windows/',
        'web/',
        'snap/',
        '.github/',
        'scripts/',
        'integration_test/',
        'assets/',
      ];
      const rootFiles = {
        'pubspec.yaml',
        'pubspec.lock',
        'config.sample.json',
        'licenses.yaml',
        'l10n.yaml',
        'analysis_options.yaml',
        'REUSE.toml',
      };
      final hits = [
        for (final path in files)
          if ((roots.any(path.startsWith) || rootFiles.contains(path)) &&
              !path.contains('/ephemeral/') &&
              !path.endsWith('GeneratedPluginRegistrant.java'))
            ..._uncreditedLines(
              path,
              RegExp('fluffychat', caseSensitive: false),
              _storeTextRoots.any(path.startsWith)
                  ? RegExp(
                      '${_docCredit.pattern}|${_absenceAssertion.pattern}',
                      caseSensitive: false,
                    )
                  : _headerCredit,
            ),
      ];
      expect(hits, isEmpty, reason: hits.take(30).join('\n'));
    });

    test('documents mention FluffyChat only as credit', () {
      final hits = [
        for (final path in [
          'README.md',
          'CONTRIBUTING.md',
          'SECURITY.md',
          'PRIVACY.md',
          'NOTICE.md',
          'CHANGELOG.md',
        ])
          ..._uncreditedLines(
            path,
            RegExp('fluffychat', caseSensitive: false),
            _docCredit,
          ),
      ];
      expect(hits, isEmpty, reason: hits.take(30).join('\n'));
    });
  });

  group('identity', () {
    String text(String path) => File(path).readAsStringSync();

    test('the app id is the same everywhere', () {
      const id = 'com.swovo.odango';
      final config = text('lib/config/app_config.dart');
      expect(config, contains("appId = '$id'"));
      expect(config, contains("appleAppGroupId = 'group.$id'"));
      expect(config, contains("pushNotificationsAppId = '$id'"));
      expect(config, contains("deepLinkPrefix = '$id://chat/'"));
      expect(config, contains("appOpenUrlScheme = '$id'"));
      expect(config, contains("pushNotificationsChannelId = 'odango_push'"));
      final gradle = text('android/app/build.gradle.kts');
      expect(gradle, contains('namespace = "$id"'));
      expect(gradle, contains('applicationId = "$id"'));
      final activity = text(
        'android/app/src/main/kotlin/com/swovo/odango/MainActivity.kt',
      );
      expect(activity, startsWith('package $id'));
      final manifest = text('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:label="Odango"'));
      expect(manifest, contains('android:scheme="$id"'));
      final project = text('ios/Runner.xcodeproj/project.pbxproj');
      expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = $id;'));
      expect(project, contains('$id.Odango-Share'));
      expect(project, contains('$id.Notification-Service-Extension'));
      for (final path in [
        'ios/Runner/Runner.entitlements',
        'ios/Odango Share/Odango Share.entitlements',
        'ios/Notification Service Extension/Notification Service Extension.entitlements',
      ]) {
        expect(text(path), contains('group.$id'), reason: path);
      }
      expect(
        text('macos/Runner/Configs/AppInfo.xcconfig'),
        contains('PRODUCT_BUNDLE_IDENTIFIER = $id'),
      );
      expect(text('linux/CMakeLists.txt'), contains('APPLICATION_ID "$id"'));
      expect(text('linux/CMakeLists.txt'), contains('BINARY_NAME "odango"'));
      expect(text('snap/snapcraft.yaml'), startsWith('name: odango'));
      expect(text('windows/runner/Runner.rc'), contains('odango.exe'));
      expect(text('web/manifest.json'), contains('"name": "Odango"'));
      expect(text('scripts/test_share_intent.sh'), contains('APP=$id'));
      expect(
        text('integration_test/share_sender/src/t197/evil/SendActivity.java'),
        contains('$id.MainActivity'),
      );
    });

    test('the product name and links default to Odango', () {
      expect(AppSettings.applicationName.defaultValue, 'Odango');
      expect(AppSettings.website.defaultValue, 'https://odango.swovo.de');
      expect(
        AppSettings.privacyPolicy.defaultValue,
        startsWith('https://odango.swovo.de/'),
      );
      expect(
        AppSettings.tos.defaultValue,
        startsWith('https://odango.swovo.de/'),
      );
      expect(
        AppSettings.logoUrl.defaultValue,
        startsWith('https://odango.swovo.de/'),
      );
      expect(
        AppSettings.repositoryUrl.defaultValue,
        'https://github.com/swovo/odango',
      );
      expect(AppSettings.koFiUrl.defaultValue, isEmpty);
      expect(AppSettings.buyMeACoffeeUrl.defaultValue, isEmpty);
    });

    test('nothing shares an identity with the upstream app', () {
      expect(
        text('lib/config/app_config.dart'),
        isNot(contains('4894dfda-c70a-4ebc-b139-acae55f3988d')),
      );
      expect(
        text('windows/installer.iss'),
        isNot(contains('4914EA58-B990-4CA5-BFAA-8EAC9A24F6A5')),
      );
      expect(
        File('ios/Runner/GoogleService-Info.plist').existsSync(),
        isFalse,
        reason: "that file configures upstream's Firebase project",
      );
      expect(File('.github/FUNDING.yml').existsSync(), isFalse);
      expect(File('.github/CODEOWNERS').existsSync(), isFalse);
      for (final path in [
        '.github/workflows/main_deploy.yaml',
        '.github/workflows/release.yaml',
      ]) {
        expect(text(path), isNot(contains('fluffychat-website')), reason: path);
        expect(text(path), isNot(contains('cname:')), reason: path);
      }
      for (final path in [
        'ios/fastlane/Matchfile',
        'macos/fastlane/Matchfile',
      ]) {
        expect(text(path), contains('ENV["MATCH_GIT_URL"]'), reason: path);
      }
    });

    test('no Apple identity or e-mail of the upstream author is left', () {
      const personal = ['4HV29TJN3A', '123574188', 'posteo', 'kussowski@'];
      final hits = <String>[];
      for (final path in files) {
        if (path == 'test/odango_rename_guard_test.dart' ||
            path == '.mailmap') {
          continue;
        }
        final text = _read(path);
        if (text == null) continue;
        for (final needle in personal) {
          if (text.contains(needle)) hits.add('$path: $needle');
        }
      }
      expect(hits, isEmpty, reason: hits.take(20).join('\n'));
      for (final path in ['ios/fastlane/Appfile', 'macos/fastlane/Appfile']) {
        final appfile = text(path);
        for (final key in ['apple_id', 'itc_team_id', 'team_id']) {
          expect(appfile, contains('$key(ENV['), reason: '$path $key');
        }
      }
      for (final path in [
        'ios/Runner.xcodeproj/project.pbxproj',
        'macos/Runner.xcodeproj/project.pbxproj',
      ]) {
        final teams = [
          for (final line in LineSplitter.split(text(path)))
            if (line.contains('DEVELOPMENT_TEAM')) line.trim(),
        ];
        expect(teams, isNotEmpty, reason: path);
        expect(teams.toSet(), {'DEVELOPMENT_TEAM = "";'}, reason: path);
      }
    });

    test('the Matrix wire names of the checkbox and account data stay', () {
      for (final MapEntry(key: name, value: reason) in _wireNames.entries) {
        final owners = [
          for (final path in files)
            if (path.startsWith('lib/') &&
                path.endsWith('.dart') &&
                (_read(path) ?? '').contains("'$name'"))
              path,
        ];
        expect(owners, hasLength(1), reason: '$name ($reason)');
      }
    });

    test('the native OIDC scheme is the reverse of the client_uri host', () {
      final host = Uri.parse(AppSettings.website.defaultValue).host;
      final reversed = host.split('.').reversed.join('.');
      expect(AppConfig.appSsoUrlScheme, reversed);
      expect(AppConfig.appSsoUrlScheme, 'de.swovo.odango');
      expect(
        text('android/app/src/main/AndroidManifest.xml'),
        contains(
          '<data android:scheme="${AppConfig.appSsoUrlScheme}" android:path="/login"/>',
        ),
      );
      final stale = [
        for (final path in files)
          if ((_read(path) ?? '').contains('com.swovo.odango.auth')) path,
      ];
      expect(
        stale.where((p) => p != 'test/odango_rename_guard_test.dart'),
        isEmpty,
      );
    });

    test('the Windows resource file has a real copyright and CRLF lines', () {
      final rc = File('windows/runner/Runner.rc').readAsBytesSync();
      final content = latin1.decode(rc);
      expect(content, contains('Odango contributors'));
      expect(content, isNot(contains('All rights reserved')));
      expect(content, isNot(contains('"com.swovo')));
      final lone = RegExp(r'(?<!\r)\n').allMatches(content);
      expect(lone, isEmpty, reason: 'Runner.rc must keep CRLF line endings');
    });

    test('no test restores the old product name as application name', () {
      final hits = [
        for (final path in files)
          if (path.startsWith('test/') &&
              path.endsWith('.dart') &&
              path != 'test/odango_rename_guard_test.dart')
            for (final line in LineSplitter.split(_read(path) ?? ''))
              if (RegExp(r'applicationName.*FluffyChat').hasMatch(line))
                '$path: ${line.trim()}',
      ];
      expect(hits, isEmpty, reason: hits.join('\n'));
    });

    test('no help link points at a donation page of the upstream author', () {
      final hits = [
        for (final path in files)
          if (path.startsWith('lib/') &&
              path.endsWith('.dart') &&
              (_read(path) ?? '').contains('ko-fi.com'))
            path,
      ];
      expect(hits, isEmpty);
    });

    test('the licence header script stamps the Odango line too', () {
      final script = text('scripts/update-license-headers.sh');
      expect(script, contains('--copyright="Odango contributors"'));
      expect(script, contains('--year="2026-Present"'));
      expect(script, contains('--copyright="Contributors to FluffyChat"'));
    });

    test('the artwork annotation overrides the aggregate AGPL one', () {
      final reuse = text('REUSE.toml');
      final art = reuse.substring(
        reuse.indexOf('# Odango app logo and generated icons'),
        reuse.indexOf('# Fonts'),
      );
      expect(art, contains('precedence = "override"'));
      expect(art, contains('LicenseRef-All-Rights-Reserved'));
      expect(art, isNot(contains('web/splash')));
      expect(reuse, contains('"test/data/**"'));
    });

    test('the fork keeps its licence and credit', () {
      expect(text('LICENSE'), contains('GNU AFFERO GENERAL PUBLIC LICENSE'));
      final readme = text('README.md');
      expect(readme, contains('AGPL-3.0'));
      expect(readme, contains('https://github.com/krille-chan/fluffychat'));
      expect(readme, contains('fork of'));
      expect(readme, contains('no migration'));
      final notice = text('NOTICE.md');
      expect(notice, contains('AGPL'));
      expect(notice, contains('https://github.com/krille-chan/fluffychat'));
      expect(text('REUSE.toml'), contains('Odango contributors'));
      for (final path in [
        'README.md',
        'CONTRIBUTING.md',
        'SECURITY.md',
        'PRIVACY.md',
        'lib/main.dart',
        'lib/config/app_config.dart',
      ]) {
        expect(
          text(path),
          contains('Contributors to FluffyChat'),
          reason: '$path lost the upstream header',
        );
      }
    });
  });
}
