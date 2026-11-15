// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat/message_ticks.dart';
import 'package:material_ui/material_ui.dart';

/// Time, "(edited)" and the delivery tick, bottom end of a bubble.
class MessageFooter extends StatelessWidget {
  final String time;
  final bool edited;
  final Tick tick;
  final Color color;

  const MessageFooter({
    required this.time,
    required this.edited,
    required this.tick,
    required this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final status = switch (tick) {
      Tick.none => null,
      Tick.sending => l10n.sending,
      Tick.sent => l10n.messageSent,
      Tick.seen => l10n.messageSeen,
      Tick.error => l10n.couldNotBeSent,
    };
    return Semantics(
      container: true,
      label: [time, if (edited) l10n.edited, ?status].join(', '),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          if (edited)
            Text(l10n.edited, style: TextStyle(color: color, fontSize: 11)),
          Text(time, style: TextStyle(color: color, fontSize: 11)),
          switch (tick) {
            Tick.none => const SizedBox.shrink(),
            Tick.sending => SizedBox.square(
              dimension: 11,
              child: CircularProgressIndicator(strokeWidth: 1, color: color),
            ),
            Tick.sent => Icon(Icons.done_rounded, size: 15, color: color),
            Tick.seen => Icon(Icons.done_all_rounded, size: 15, color: color),
            Tick.error => Icon(Icons.error_rounded, size: 15, color: color),
          },
        ],
      ),
    );
  }
}
