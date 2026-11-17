// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/topics/topic.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:material_ui/material_ui.dart';

/// The topics as chips under the header (DESIGN 9.12, mockup 1h): General,
/// the busiest topics, then a chip that opens the whole list.
class TopicChipBar extends StatelessWidget {
  const TopicChipBar({
    required this.topics,
    required this.activeThreadId,
    required this.onGeneral,
    required this.onTopic,
    required this.onAll,
    super.key,
  });

  final List<Topic> topics;
  final String? activeThreadId;
  final VoidCallback onGeneral;
  final void Function(Topic topic) onTopic;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final shown = topics.take(AppTopics.maxChips).toList();
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.xxl,
        end: AppSpacing.xxl,
        top: AppSpacing.s,
      ),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppTopics.chipBarHeight / 2),
        child: SizedBox(
          height: AppTopics.chipBarHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
            children: [
              _Chip(
                key: const ValueKey('topic_chip_general'),
                icon: TopicIcons.of(TopicIcons.fallback),
                label: l10n.topicGeneral,
                selected: activeThreadId == null,
                onTap: onGeneral,
              ),
              for (final topic in shown)
                _Chip(
                  key: ValueKey('topic_chip_${topic.rootEventId}'),
                  icon: TopicIcons.of(topic.icon),
                  label: topic.title.isEmpty ? l10n.topicUntitled : topic.title,
                  count: topic.unread,
                  selected: activeThreadId == topic.rootEventId,
                  onTap: () => onTopic(topic),
                ),
              _Chip(
                key: const ValueKey('topic_chip_all'),
                icon: Icons.view_list_rounded,
                label: l10n.topics,
                selected: false,
                onTap: onAll,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count = 0,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = selected ? tokens.acc : tokens.fg;
    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? '$label, $count' : label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTopics.chipHeight / 2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppTopics.chipTap,
            minHeight: AppTopics.chipTap,
          ),
          child: Center(
            child: Container(
              height: AppTopics.chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? tokens.accs : tokens.surf2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 5,
                children: [
                  Icon(icon, size: 16, color: color),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (count > 0)
                    Text(
                      count >= 99 ? '99+' : '$count',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
