// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The line above the composer that names the topic a message goes to.
class SendingToBar extends StatelessWidget {
  const SendingToBar({required this.title, super.key});

  /// Already cleaned (see `TopicParser.titleFrom`); empty means untitled.
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final text = l10n.sendingToTopic(
      title.isEmpty ? l10n.topicUntitled : title,
    );
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: AppSpacing.xxl,
          end: AppSpacing.xxl,
          bottom: AppSpacing.xs,
        ),
        child: Row(
          spacing: AppSpacing.xxs,
          children: [
            Icon(Icons.tag_rounded, size: 15, color: tokens.acc),
            Expanded(
              child: Text(
                text,
                key: const ValueKey('sending_to_topic'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.acc,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
