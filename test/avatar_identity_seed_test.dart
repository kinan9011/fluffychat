// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/pages/chat/chat_view.dart';
import 'package:odango/pages/chat/events/html_message.dart';
import 'package:odango/pages/chat/mention_suggestion_tile.dart';
import 'package:odango/pages/key_verification/key_verification_dialog.dart';
import 'package:odango/utils/string_color.dart';
import 'package:odango/widgets/avatar.dart';

import 'utils/chat_page_harness.dart';
import 'utils/golden.dart';

/// Avatar colour is a recognition aid for people and rooms. Derived from the
/// display name it can be copied by anybody (W01 security L2), so every
/// `Avatar(` must say where its colour comes from.
const _allowlist = <String, String>{};

String _callAt(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (char == '(') depth++;
    if (char == ')') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return source.substring(open);
}

void main() {
  test('every Avatar( names a colour seed or a presence user', () {
    final pattern = RegExp(r'(?<![A-Za-z_])Avatar\(');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path == 'lib/widgets/avatar.dart') continue;
      final source = file.readAsStringSync();
      var index = 0;
      for (final match in pattern.allMatches(source)) {
        index++;
        final call = _callAt(source, match.end - 1);
        final seeded =
            call.contains('colorSeed:') || call.contains('presenceUserId:');
        if (seeded) continue;
        final key = '${file.path}#$index';
        if (!_allowlist.containsKey(key)) offenders.add(key);
      }
    }
    expect(offenders, isEmpty);
  });

  test('allowlist entries explain themselves', () {
    for (final entry in _allowlist.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
    }
  });

  final displayName = RegExp(
    r'colorSeed:\s*([^,)]*(displayname|displayName|calcDisplayname|\.name\b|getLocalizedDisplayname)|(title|name|label|username|userName)\s*[,)])',
  );

  test('the guard recognises the ways a display name gets in (SEC L5)', () {
    for (final bad in [
      'colorSeed: user.displayName,',
      'colorSeed: title,',
      'colorSeed: name)',
      'colorSeed: room.getLocalizedDisplayname(),',
      'colorSeed: user.calcDisplayname()',
    ]) {
      expect(displayName.hasMatch(bad), isTrue, reason: bad);
    }
    for (final good in [
      'colorSeed: user.id,',
      'colorSeed: room.avatarColorSeed,',
      'colorSeed: mxid,',
      'colorSeed: namespace,',
    ]) {
      expect(displayName.hasMatch(good), isFalse, reason: good);
    }
  });

  test('a colour seed is never a display name', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      if (displayName.hasMatch(source)) offenders.add(file.path);
    }
    expect(offenders, isEmpty);
  });

  group('colour follows the Matrix ID, not the display name', () {
    final harness = ChatPageHarness();
    late Client client;

    setUpAll(() async {
      await harness.setUpAll();
      client = harness.client;
    });

    Color fill(WidgetTester tester, [Type? scope]) {
      final avatar = scope == null
          ? find.byType(Avatar)
          : find.descendant(
              of: find.byType(scope),
              matching: find.byType(Avatar),
            );
      final container = tester.widget<Container>(
        find.descendant(of: avatar, matching: find.byType(Container)).first,
      );
      return (container.decoration! as BoxDecoration).color!;
    }

    Widget tile(String mxid, String displayname) => MentionSuggestionTile(
      suggestion: {
        'type': 'user',
        'mxid': mxid,
        'displayname': displayname,
        'avatar_url': null,
      },
      client: client,
      size: 40,
      onTap: () {},
    );

    testWidgets('mention suggestions: same display name, different ID', (
      tester,
    ) async {
      await pumpGoldenWidget(tester, tile('@mara:example.org', 'Mara'));
      final real = fill(tester);
      await pumpGoldenWidget(tester, tile('@fake:evil.example', 'Mara'));
      final fake = fill(tester);
      expect(real, '@mara:example.org'.avatarColor);
      expect(fake, '@fake:evil.example'.avatarColor);
      expect(real, isNot(fake));
      expect(real, isNot('Mara'.avatarColor));
    });

    testWidgets('mention suggestions: renaming keeps the colour', (
      tester,
    ) async {
      await pumpGoldenWidget(tester, tile('@mara:example.org', 'Mara'));
      final before = fill(tester);
      await pumpGoldenWidget(tester, tile('@mara:example.org', 'Somebody'));
      expect(fill(tester), before);
    });

    testWidgets('key verification waiting screen uses the requester ID', (
      tester,
    ) async {
      harness.setUp();
      await harness.open(tester);
      final context = tester.element(find.byType(ChatView));
      Future<Color> waiting(String userId) async {
        final request = KeyVerification(
          encryption: client.encryption!,
          userId: userId,
        );
        unawaited(KeyVerificationDialog(request: request).show(context));
        await harness.settle(tester, rounds: 3);
        expect(request.state, KeyVerificationState.waitingAccept);
        final color = fill(tester, KeyVerificationDialog);
        Navigator.of(tester.element(find.byType(KeyVerificationDialog))).pop();
        await harness.settle(tester, rounds: 3);
        return color;
      }

      expect(
        await waiting('@mara:example.org'),
        '@mara:example.org'.avatarColor,
      );
      final other = await waiting('@mara:evil.example');
      expect(other, '@mara:evil.example'.avatarColor);
      expect(other, isNot('@mara:example.org'.avatarColor));
      await harness.finish(tester);
      await harness.tearDown();
    });

    testWidgets('mention pill colour follows the ID', (tester) async {
      harness.setUp();
      await harness.open(tester);
      final context = tester.element(find.byType(ChatView));
      Future<Color> pill(String id, String name) async {
        unawaited(
          showDialog<void>(
            context: context,
            builder: (dialogContext) => Material(
              type: MaterialType.transparency,
              child: Center(
                child: MatrixPill(
                  name: name,
                  colorSeed: id,
                  outerContext: dialogContext,
                  uri: 'https://matrix.to/#/$id',
                  fontSize: 14,
                  color: null,
                ),
              ),
            ),
          ),
        );
        await harness.settle(tester, rounds: 3);
        final color = fill(tester, MatrixPill);
        Navigator.of(tester.element(find.byType(MatrixPill))).pop();
        await harness.settle(tester, rounds: 3);
        return color;
      }

      final real = await pill('@mara:example.org', 'Mara');
      final fake = await pill('@fake:evil.example', 'Mara');
      expect(real, '@mara:example.org'.avatarColor);
      expect(real, isNot(fake));
      await harness.finish(tester);
      await harness.tearDown();
    });
  });
}
