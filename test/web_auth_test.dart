// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/sign_in_flows/web_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final calls = <String>[];

  Future<String> fakeAuthenticate({
    required String url,
    required String callbackUrlScheme,
    required FlutterWebAuth2Options options,
  }) async {
    calls.add(url);
    return 'app://done?code=1';
  }

  Future<String> run(String url) => authenticateInBrowser(
    url: url,
    callbackUrlScheme: 'app',
    authenticate: fakeAuthenticate,
  );

  setUp(calls.clear);

  group('hostile sign-in addresses from a server are refused', () {
    for (final url in [
      'file:///etc/passwd',
      'file://attacker.example/share/x.exe',
      'intent://x#Intent;scheme=a;end',
      'javascript:alert(1)',
      'search-ms:query=x',
      'smb://attacker.example/share',
      'custom-app://login',
      'ms-msdt:/id PCWDiagnostic',
      'data:text/html,hi',
      '',
      '   ',
      '/relative/path',
      'login.example.org/auth',
      'https://',
      'http:///nohost',
      r'C:\Windows\System32\calc.exe',
    ]) {
      test('"$url"', () async {
        await expectLater(run(url), throwsA(isA<UnsafeAuthUrlException>()));
        expect(calls, isEmpty);
      });
    }
  });

  group('web addresses keep working, including local test servers', () {
    for (final url in [
      'https://auth.example.org/authorize?client_id=x&state=y',
      'http://localhost:8008/_matrix/client/v3/login/sso/redirect',
      'http://10.0.2.2:8008/authorize',
      'http://127.0.0.1:8448/a',
      'https://[::1]:8448/a',
    ]) {
      test(url, () async {
        expect(await run(url), 'app://done?code=1');
        expect(calls, [url]);
      });
    }
  });

  testWidgets('the refusal has a readable message', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      const UnsafeAuthUrlException().toLocalizedString(context),
      L10n.of(context).unsafeSignInUrl,
    );
  });

  test('flutter_web_auth_2 is only used by the checked wrapper', () {
    final pattern = RegExp(
      r'''^\s*(import|export)\s+['"]package:flutter_web_auth_2''',
      multiLine: true,
    );
    final importers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => pattern.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toSet();
    expect(importers, {'lib/utils/sign_in_flows/web_auth.dart'});
  });
}
