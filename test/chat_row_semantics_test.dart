// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/chat_list/chat_row_model.dart';

void main() {
  Future<L10n> english(WidgetTester tester) async {
    late L10n l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = L10n.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return l10n;
  }

  String label(
    L10n l10n, {
    int unread = 0,
    bool pinned = false,
    bool muted = false,
    bool mentioned = false,
    bool markedUnread = false,
  }) => chatRowSemantics(
    l10n,
    name: 'Mara',
    unread: unread,
    preview: 'see you',
    time: '12:40',
    pinned: pinned,
    muted: muted,
    markedUnread: markedUnread,
    mentioned: mentioned,
  );

  testWidgets('name, unread count, preview, time, then the states', (
    tester,
  ) async {
    final l10n = await english(tester);
    expect(
      label(l10n, unread: 3, pinned: true, muted: true, mentioned: true),
      'Mara, 3 unread, last message see you, 12:40, Pinned, Muted, Mention',
    );
  });

  testWidgets('every state has its own word', (tester) async {
    final l10n = await english(tester);
    expect(label(l10n), 'Mara, last message see you, 12:40');
    expect(label(l10n, muted: true), endsWith(', Muted'));
    expect(label(l10n, pinned: true), endsWith(', Pinned'));
    expect(label(l10n, mentioned: true), endsWith(', Mention'));
    expect(label(l10n, markedUnread: true), endsWith(', Unread'));
  });

  testWidgets('a muted chat that mentions you says both', (tester) async {
    final l10n = await english(tester);
    final text = label(l10n, muted: true, mentioned: true);
    expect(text, contains('Muted'));
    expect(text, contains('Mention'));
  });
}
