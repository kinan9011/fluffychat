// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings/settings_group.dart';
import 'package:fluffychat/widgets/settings/settings_row.dart';
import 'package:fluffychat/widgets/settings/settings_scaffold.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class SettingsData extends StatelessWidget {
  const SettingsData({super.key});

  static const maxRooms = 200;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final client = Matrix.of(context).client;
    final rooms = client.rooms
        .where((room) => room.membership == Membership.join)
        .take(maxRooms)
        .toList();
    return SettingsScaffold(
      title: l10n.settingsDataAndStorage,
      children: [
        SettingsGroup(
          header: l10n.exportPickChat,
          footer: l10n.dataStorageNote,
          rows: [
            for (final room in rooms)
              SettingsRow(
                key: ValueKey('export_room_${room.id}'),
                leading: Avatar(
                  mxContent: room.avatar,
                  name: room.getLocalizedDisplayname(MatrixLocals(l10n)),
                  colorSeed: room.avatarColorSeed,
                  size: 32,
                ),
                title: safeDisplayText(
                  room.getLocalizedDisplayname(MatrixLocals(l10n)),
                  maxGraphemes: 60,
                ),
                trailing: Icon(
                  Icons.download_rounded,
                  size: 20,
                  color: tokens.mut,
                ),
                onTap: () => context.go(
                  Uri(
                    path: '/settings/data/export',
                    queryParameters: {'room': room.id},
                  ).toString(),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
