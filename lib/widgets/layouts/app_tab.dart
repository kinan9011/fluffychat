// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

enum AppTab {
  chats('/rooms', Icons.chat_outlined, Icons.chat_rounded),
  calls('/calls', Icons.call_outlined, Icons.call_rounded),
  settings('/settings', Icons.settings_outlined, Icons.settings_rounded),
  profile('/profile', null, null);

  final String path;

  final IconData? icon;
  final IconData? activeIcon;

  const AppTab(this.path, this.icon, this.activeIcon);

  String label(L10n l10n) => switch (this) {
    chats => l10n.chats,
    calls => l10n.calls,
    settings => l10n.settings,
    profile => l10n.profile,
  };

  static List<AppTab> visible({required bool callsEnabled}) => [
    for (final tab in values)
      if (tab != calls || callsEnabled) tab,
  ];

  static AppTab? forPath(String path) {
    for (final tab in values) {
      if (path == tab.path || path.startsWith('${tab.path}/')) return tab;
    }
    return null;
  }

  static bool isRoot(String path) => values.any((tab) => tab.path == path);
}
