// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

enum SendOption { silent, schedule, whenOnline }

final _command = RegExp(r'^/\w+');

/// What holding the send button offers. Nothing for an empty message, an edit
/// (an edit has no time of its own), a command, or a room the user cannot
/// write in. "When online" needs a partner whose presence is known and not
/// online yet.
List<SendOption> availableSendOptions({
  required String text,
  required bool editing,
  required bool canSend,
  required bool partnerPresenceKnownOffline,
}) {
  if (!canSend || editing || text.trim().isEmpty) return const [];
  if (_command.hasMatch(text)) return const [];
  return [
    SendOption.silent,
    SendOption.schedule,
    if (partnerPresenceKnownOffline) SendOption.whenOnline,
  ];
}

/// Whether "send when online" makes sense: the partner is not online and the
/// server told us when they were last active. A server that hides presence
/// answers "offline" for everyone without a last activity: that is not known.
bool presenceKnownOffline({required bool online, DateTime? lastActive}) =>
    !online && lastActive != null;
