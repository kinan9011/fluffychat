// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The redesigned screens an accessibility matrix opens, as routes of the fake
/// account. `{room}` is the id of the joined room of the harness.
const a11yScreens = <String>[
  '/rooms',
  '/rooms/archive',
  '/rooms/newprivatechat',
  '/rooms/newgroup',
  '/rooms/search',
  '/rooms/{room}',
  '/rooms/{room}/topics',
  '/rooms/{room}/appearance',
  '/rooms/{room}/scheduled',
  '/rooms/{room}/details',
  '/settings',
  '/settings/data',
  '/settings/data/export',
  '/settings/notifications',
  '/settings/appearance',
  '/settings/devices',
  '/settings/chat',
  '/settings/chat/folders',
  '/settings/chat/emotes',
  '/settings/homeserver',
  '/settings/security',
  '/profile',
  '/calls',
];

String a11yPath(String screen, String roomId) =>
    screen.replaceAll('{room}', Uri.encodeComponent(roomId));
