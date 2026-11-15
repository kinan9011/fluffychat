// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/utils/chat_list/folder_store.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/chat_list_room_extension.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/space_fixtures.dart';
import 'utils/test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client first;
  late Client second;
  late FakeMatrixApi apiFirst;
  late FakeMatrixApi apiSecond;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    first = await prepareTestClient();
    first.backgroundSync = false;
    apiFirst = FakeMatrixApi.currentApi!;
    FakeMatrixApi.client = first;
    second = await prepareTestClient(clientName: 'Second');
    second.backgroundSync = false;
    apiSecond = FakeMatrixApi.currentApi!;
    FakeMatrixApi.client = second;
  });

  tearDown(() {
    AppRoutes.isLoggedIn = AppRoutes.defaultIsLoggedIn;
    first.accountData.remove(FolderStore.accountDataType);
    second.accountData.remove(FolderStore.accountDataType);
    first.rooms.removeWhere((room) => room.id.startsWith('!fo'));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void withFolders(Client client, List<Map<String, Object?>> folders) {
    client.accountData[FolderStore.accountDataType] = BasicEvent(
      type: FolderStore.accountDataType,
      content: {'version': 1, 'folders': folders},
    );
  }

  String location() =>
      FluffyChatApp.router.routeInformationProvider.value.uri.toString();

  Future<MatrixState> pumpAt(
    WidgetTester tester,
    String path, {
    double width = 400,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      FluffyChatApp(
        clients: [first, second],
        store: prefs,
        appLockSettings: (pincode: null, useBiometrics: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final matrix = tester.state<MatrixState>(find.byType(Matrix));
    matrix.setActiveClient(first);
    FluffyChatApp.router.go(path);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    return matrix;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 35));
    }
  }

  List<Object?> puts(FakeMatrixApi api) {
    FakeMatrixApi.currentApi = api;
    return FakeMatrixApi.calledEndpoints.entries
        .where(
          (e) => e.key.endsWith('/account_data/${FolderStore.accountDataType}'),
        )
        .expand((e) => e.value)
        .toList();
  }

  Map<String, Object?> folder(
    String id,
    String name, {
    List<String>? rooms,
    List<String> types = const ['group'],
  }) => {'id': id, 'name': name, 'types': types, 'rooms': rooms ?? <String>[]};

  testWidgets('create a folder with a name and Groups', (tester) async {
    FakeMatrixApi.currentApi = apiFirst;
    FakeMatrixApi.calledEndpoints.clear();
    await pumpAt(tester, '/settings/chat/folders');
    expect(
      find.text(
        'Folders sync to your other devices through your homeserver. They are not end-to-end encrypted.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Create folder'));
    await settle(tester);
    expect(location(), '/settings/chat/folders/edit');
    await tester.enterText(find.byKey(const ValueKey('folder_name')), 'Work');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Groups'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save_folder')));
    await settle(tester);

    final bodies = puts(apiFirst);
    expect(bodies, hasLength(1));
    final body = jsonDecode(bodies.single! as String) as Map<String, Object?>;
    final folders = body['folders']! as List;
    final id = (folders.single as Map)['id'];
    expect(id, matches(RegExp(r'^[a-z0-9]{8}$')));
    expect(body, {
      'version': 1,
      'folders': [
        {
          'id': id,
          'name': 'Work',
          'types': ['group'],
          'rooms': <String>[],
          'exclude_muted': false,
          'exclude_read': false,
        },
      ],
    });
    expect(puts(apiSecond), isEmpty);
    expect(location(), '/settings/chat/folders');
    expect(find.widgetWithText(ListTile, 'Work'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a folder cannot be saved without a name', (tester) async {
    await pumpAt(tester, '/settings/chat/folders/edit');
    final save = find.byKey(const ValueKey('save_folder'));
    expect(tester.widget<TextButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('folder_name')), ' ');
    await tester.pump();
    expect(tester.widget<TextButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('folder_name')), 'A');
    await tester.pump();
    expect(tester.widget<TextButton>(save).onPressed, isNotNull);
    await finish(tester);
  });

  testWidgets('a newer document is read-only: notice, no create button', (
    tester,
  ) async {
    first.accountData[FolderStore.accountDataType] = BasicEvent(
      type: FolderStore.accountDataType,
      content: {'version': 2, 'folders': <Object?>[]},
    );
    await pumpAt(tester, '/settings/chat/folders');
    expect(
      find.text(
        "These folders were made with a newer version of the app and can't be edited here.",
      ),
      findsOneWidget,
    );
    expect(find.text('Create folder'), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'an oversized document is unreadable: own notice, no create button, no write',
    (tester) async {
      first.accountData[FolderStore.accountDataType] = BasicEvent(
        type: FolderStore.accountDataType,
        content: {
          'version': 1,
          'folders': [
            for (var i = 0; i < 4; i++)
              folder(
                'big$i',
                'Big$i',
                rooms: [
                  for (var j = 0; j < 500; j++)
                    '!${(i * 500 + j).toString().padLeft(18, 'a')}:matrix.org',
                ],
              ),
          ],
        },
      );
      FakeMatrixApi.currentApi = apiFirst;
      FakeMatrixApi.calledEndpoints.clear();
      await pumpAt(tester, '/settings/chat/folders');
      expect(
        find.textContaining("These folders can't be read or are too big"),
        findsOneWidget,
      );
      expect(
        find.text(
          "These folders were made with a newer version of the app and can't be edited here.",
        ),
        findsNothing,
      );
      expect(find.text('Create folder'), findsNothing);
      expect(puts(apiFirst), isEmpty);
      await finish(tester);
    },
  );

  testWidgets('saving past the size cap shows a clear error and writes nothing', (
    tester,
  ) async {
    List<Map<String, Object?>> four(int count) {
      final rooms = [
        for (var i = 0; i < count; i++)
          '!${i.toString().padLeft(18, 'a')}:matrix.org',
      ];
      return [
        for (var k = 0; k < 4; k++)
          folder('f$k', 'F$k', rooms: rooms.skip(k * 500).take(500).toList()),
      ];
    }

    int bytes(int count) =>
        utf8.encode(jsonEncode({'version': 1, 'folders': four(count)})).length;
    var count = 1800;
    while (bytes(count + 1) < 65536 - 40) {
      count++;
    }
    withFolders(first, four(count));
    expect(FolderStore.of(first).readOnly, isFalse);
    FakeMatrixApi.currentApi = apiFirst;
    FakeMatrixApi.calledEndpoints.clear();
    await pumpAt(tester, '/settings/chat/folders/edit');
    await tester.enterText(
      find.byKey(const ValueKey('folder_name')),
      'One more folder with a name',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save_folder')));
    await settle(tester);
    expect(
      find.text(
        'Your folders hold too many chats to sync. Remove some chats from your folders and try again.',
      ),
      findsOneWidget,
    );
    expect(puts(apiFirst), isEmpty);
    await finish(tester);
  });

  testWidgets('a deep link to a new folder with 30 folders cannot save', (
    tester,
  ) async {
    withFolders(first, [for (var i = 0; i < 30; i++) folder('f$i', 'F$i')]);
    FakeMatrixApi.currentApi = apiFirst;
    FakeMatrixApi.calledEndpoints.clear();
    await pumpAt(tester, '/settings/chat/folders/edit');
    expect(find.text('You can have up to 30 folders'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('folder_name')), 'More');
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('save_folder')))
          .onPressed,
      isNull,
    );
    expect(puts(apiFirst), isEmpty);
    await finish(tester);
  });

  testWidgets('the folder list does not count archived chats', (tester) async {
    first.rooms.addAll([
      testSpaceChild(first, '!foa:x'),
      testSpaceChild(first, '!fob:x', tags: [archivedTag]),
    ]);
    withFolders(first, [
      folder('k1', 'Family', rooms: ['!foa:x', '!fob:x'], types: []),
    ]);
    await pumpAt(tester, '/settings/chat/folders');
    expect(find.text('1 chats'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('30 folders disable create and say why', (tester) async {
    withFolders(first, [for (var i = 0; i < 30; i++) folder('f$i', 'F$i')]);
    await pumpAt(tester, '/settings/chat/folders');
    expect(find.text('You can have up to 30 folders'), findsOneWidget);
    final tile = tester.widget<ListTile>(
      find.byKey(const ValueKey('create_folder')),
    );
    expect(tile.enabled, isFalse);
    expect(tile.onTap, isNull);
    await finish(tester);
  });

  testWidgets('a folder name is plain text, never markup', (tester) async {
    withFolders(first, [folder('k1', '<b>x</b>')]);
    await pumpAt(tester, '/settings/chat/folders');
    expect(find.text('<b>x</b>'), findsOneWidget);
    expect(tester.widget<Text>(find.text('<b>x</b>')).maxLines, 1);
    await finish(tester);
  });

  testWidgets('delete asks first, then saves without the folder', (
    tester,
  ) async {
    withFolders(first, [folder('k1', 'Work'), folder('k2', 'Home')]);
    FakeMatrixApi.currentApi = apiFirst;
    FakeMatrixApi.calledEndpoints.clear();
    await pumpAt(tester, '/settings/chat/folders/edit?id=k1');
    await tester.tap(find.byKey(const ValueKey('delete_folder')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Delete the folder "Work"? The chats stay where they are.'),
      findsOneWidget,
    );
    expect(puts(apiFirst), isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await settle(tester);
    final body =
        jsonDecode(puts(apiFirst).single! as String) as Map<String, Object?>;
    expect((body['folders']! as List).map((f) => (f as Map)['id']), ['k2']);
    expect(location(), '/settings/chat/folders');
    await finish(tester);
  });

  testWidgets('cancelling the delete dialog keeps the folder', (tester) async {
    withFolders(first, [folder('k1', 'Work')]);
    FakeMatrixApi.currentApi = apiFirst;
    FakeMatrixApi.calledEndpoints.clear();
    await pumpAt(tester, '/settings/chat/folders/edit?id=k1');
    await tester.tap(find.byKey(const ValueKey('delete_folder')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await settle(tester);
    expect(puts(apiFirst), isEmpty);
    expect(location(), '/settings/chat/folders/edit?id=k1');
    await finish(tester);
  });

  testWidgets('a new folder is added to the existing ones', (tester) async {
    withFolders(first, [folder('k1', 'Work')]);
    FakeMatrixApi.currentApi = apiFirst;
    FakeMatrixApi.calledEndpoints.clear();
    await pumpAt(tester, '/settings/chat/folders/edit');
    await tester.enterText(find.byKey(const ValueKey('folder_name')), 'Home');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save_folder')));
    await settle(tester);
    final body =
        jsonDecode(puts(apiFirst).single! as String) as Map<String, Object?>;
    expect((body['folders']! as List).map((f) => (f as Map)['name']).toList(), [
      'Work',
      'Home',
    ]);
    await finish(tester);
  });

  testWidgets('editing keeps the other folders and the folder position', (
    tester,
  ) async {
    withFolders(first, [folder('k1', 'Work'), folder('k2', 'Home')]);
    FakeMatrixApi.currentApi = apiFirst;
    FakeMatrixApi.calledEndpoints.clear();
    await pumpAt(tester, '/settings/chat/folders/edit?id=k1');
    await tester.enterText(find.byKey(const ValueKey('folder_name')), 'Job');
    await tester.tap(find.byKey(const ValueKey('save_folder')));
    await settle(tester);
    final body =
        jsonDecode(puts(apiFirst).single! as String) as Map<String, Object?>;
    expect((body['folders']! as List).map((f) => (f as Map)['name']).toList(), [
      'Job',
      'Home',
    ]);
    await finish(tester);
  });

  testWidgets('the editor closes when the active account changes', (
    tester,
  ) async {
    withFolders(first, [folder('k1', 'Work')]);
    final matrix = await pumpAt(tester, '/settings/chat/folders/edit?id=k1');
    expect(find.byKey(const ValueKey('folder_name')), findsOneWidget);
    matrix.setActiveClient(second);
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('folder_name')), findsNothing);
    expect(puts(apiSecond), isEmpty);
    await finish(tester);
  });

  testWidgets('a folder tab filters the list and has an edit menu', (
    tester,
  ) async {
    first.rooms.addAll([
      testSpaceChild(first, '!foa:x'),
      testSpaceChild(first, '!fob:x'),
    ]);
    withFolders(first, [
      folder('k1', 'Family', rooms: ['!foa:x'], types: []),
    ]);
    await pumpAt(tester, '/rooms');
    expect(find.byKey(const Key('chat_list_item_!fob:x')), findsOneWidget);
    await tester.ensureVisible(find.text('Family'));
    await tester.tap(find.text('Family'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('chat_list_item_!foa:x')), findsOneWidget);
    expect(find.byKey(const Key('chat_list_item_!fob:x')), findsNothing);

    await tester.longPress(find.text('Family'));
    await settle(tester);
    expect(find.text('Edit folder'), findsOneWidget);
    expect(find.text('Delete folder'), findsOneWidget);
    await tester.tap(find.text('Edit folder'));
    await settle(tester);
    expect(location(), '/settings/chat/folders/edit?id=k1');
    await finish(tester);
  });

  testWidgets('the tab menu works again after editing the folder', (
    tester,
  ) async {
    first.rooms.add(testSpaceChild(first, '!foa:x'));
    withFolders(first, [
      folder('k1', 'Family', rooms: ['!foa:x'], types: []),
    ]);
    FakeMatrixApi.currentApi = apiFirst;
    await pumpAt(tester, '/rooms');
    await tester.ensureVisible(find.text('Family'));
    await tester.tap(find.text('Family'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(find.text('Family'));
    await settle(tester);
    await tester.tap(find.text('Edit folder'));
    await settle(tester);
    expect(location(), '/settings/chat/folders/edit?id=k1');
    await tester.enterText(find.byKey(const ValueKey('folder_name')), 'Kin');
    await tester.tap(find.byKey(const ValueKey('save_folder')));
    await settle(tester);
    FluffyChatApp.router.go('/rooms');
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Kin'), findsOneWidget);
    await tester.longPress(find.text('Kin'));
    await settle(tester);
    expect(find.text('Delete folder'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('removing the selected folder falls back to All chats', (
    tester,
  ) async {
    first.rooms.add(testSpaceChild(first, '!foa:x'));
    withFolders(first, [
      folder('k1', 'Family', rooms: ['!foa:x'], types: []),
    ]);
    await pumpAt(tester, '/rooms');
    await tester.ensureVisible(find.text('Family'));
    await tester.tap(find.text('Family'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => first.handleSync(
        SyncUpdate(
          nextBatch: 'x',
          accountData: [
            BasicEvent(
              type: FolderStore.accountDataType,
              content: {'version': 1, 'folders': <Object?>[]},
            ),
          ],
        ),
      ),
    );
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Family'), findsNothing);
    expect(find.byKey(const Key('chat_list_item_!foa:x')), findsOneWidget);
    await finish(tester);
  });
}
