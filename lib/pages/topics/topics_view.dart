// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/topics/topic_row.dart';
import 'package:fluffychat/pages/topics/topics_page.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/topics/topic.dart';
import 'package:fluffychat/utils/topics/topics_model.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class TopicsView extends StatelessWidget {
  const TopicsView(this.controller, {super.key});

  final TopicsController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final c = controller;
    final room = c.room;
    if (room == null) {
      return Scaffold(
        backgroundColor: tokens.bg,
        body: Center(child: Text(l10n.youAreNoLongerParticipatingInThisChat)),
      );
    }
    final model = c.model;
    return Scaffold(
      backgroundColor: tokens.bg,
      floatingActionButton: c.supported && c.canCreate
          ? _NewTopicButton(onTap: c.newTopic)
          : null,
      body: SafeArea(
        child: Column(
          children: [
            _Header(room: room, model: model),
            _Segments(onChat: c.openGeneral),
            Expanded(
              child: !c.supported
                  ? _Message(text: l10n.topicsUnavailable)
                  : model == null
                  ? const _Skeleton()
                  : _List(controller: c, model: model, room: room),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.room, required this.model});

  final Room room;
  final TopicsModel? model;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final name = safeDisplayText(
      room.getLocalizedDisplayname(MatrixLocals(l10n)),
      maxGraphemes: 80,
    );
    final members = room.summary.mJoinedMemberCount ?? 0;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 2, 14, 12),
      child: Row(
        spacing: AppSpacing.m,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tokens.surf2,
              shape: BoxShape.circle,
            ),
            child: const BackButton(),
          ),
          Avatar(
            mxContent: room.avatar,
            name: name,
            colorSeed: room.avatarColorSeed,
            size: 40,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (model != null)
                  ValueListenableBuilder(
                    valueListenable: model!.topics,
                    builder: (context, topics, _) => Text(
                      '${l10n.topicCount(topics.length)} · ${l10n.countParticipants(members)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.mut, fontSize: 12.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.onChat});

  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.only(start: 14, end: 14, bottom: 10),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surf2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              selected: true,
              button: true,
              label: l10n.topics,
              excludeSemantics: true,
              child: Container(
                height: AppTopics.segmentHeight,
                decoration: BoxDecoration(
                  color: tokens.surf,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.shadow,
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: _SegmentLabel(
                  icon: Icons.view_list_rounded,
                  text: l10n.topics,
                  color: tokens.fg,
                ),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: l10n.asOneChat,
              excludeSemantics: true,
              onTap: onChat,
              child: InkWell(
                key: const ValueKey('topics_as_one_chat'),
                onTap: onChat,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: AppTopics.segmentHeight + 10,
                  alignment: Alignment.center,
                  child: _SegmentLabel(
                    icon: Icons.chat_rounded,
                    text: l10n.asOneChat,
                    color: tokens.mut,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 5,
    children: [
      Icon(icon, size: 18, color: color),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _List extends StatelessWidget {
  const _List({
    required this.controller,
    required this.model,
    required this.room,
  });

  final TopicsController controller;
  final TopicsModel model;
  final Room room;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ValueListenableBuilder(
      valueListenable: model.status,
      builder: (context, status, _) => ValueListenableBuilder(
        valueListenable: model.topics,
        builder: (context, topics, _) {
          if (status == TopicsStatus.loading && topics.isEmpty) {
            return const _Skeleton();
          }
          if (status == TopicsStatus.failed) {
            return _Message(
              text: l10n.topicsLoadFailed,
              action: l10n.tryAgain,
              onAction: controller.retry,
            );
          }
          final general = _general(context, room);
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: topics.length + 1 + (topics.isEmpty ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == 0) {
                return TopicRow(
                  key: const ValueKey('topic_general'),
                  topic: general,
                  onTap: controller.openGeneral,
                );
              }
              if (topics.isEmpty) {
                return _Message(text: l10n.topicsEmpty, scroll: false);
              }
              final topic = topics[index - 1];
              return TopicRow(
                key: ValueKey('topic_${topic.rootEventId}'),
                topic: topic,
                onTap: () => controller.openTopic(topic),
              );
            },
          );
        },
      ),
    );
  }

  Topic _general(BuildContext context, Room room) {
    final last = room.lastEvent;
    final main =
        last != null && last.relationshipType != RelationshipTypes.thread;
    return Topic(
      rootEventId: '',
      title: L10n.of(context).topicGeneral,
      icon: TopicIcons.fallback,
      replyCount: 0,
      lastActivity: main ? last.originServerTs : room.latestEventReceivedTime,
      hue: 268,
      lastPreview: main
          ? safeDisplayText(
              last.calcLocalizedBodyFallback(
                MatrixLocals(L10n.of(context)),
                hideReply: true,
                hideEdit: true,
                plaintextBody: true,
              ),
              maxGraphemes: TopicParser.previewMax,
            )
          : '',
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    this.action,
    this.onAction,
    this.scroll = true,
  });

  final String text;
  final String? action;
  final VoidCallback? onAction;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final body = Padding(
      padding: const EdgeInsets.all(AppSpacing.huge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.xl,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.mut, fontSize: 14.5, height: 1.4),
          ),
          if (action != null)
            TextButton(
              key: const ValueKey('topics_retry'),
              onPressed: onAction,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Text(action!),
            ),
        ],
      ),
    );
    return scroll ? Center(child: body) : body;
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      children: [
        for (var i = 0; i < 6; i++)
          SizedBox(
            height: AppTopics.rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: Row(
                spacing: AppSpacing.l,
                children: [
                  Container(
                    width: AppTopics.iconTile,
                    height: AppTopics.iconTile,
                    decoration: BoxDecoration(
                      color: tokens.surf2,
                      borderRadius: BorderRadius.circular(
                        AppTopics.iconTileRadius,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Container(width: 120, height: 12, color: tokens.surf2),
                        Container(height: 10, color: tokens.surf2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _NewTopicButton extends StatelessWidget {
  const _NewTopicButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final label = L10n.of(context).newTopic;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: tokens.acc,
        elevation: 4,
        shadowColor: tokens.shadow,
        borderRadius: BorderRadius.circular(AppTopics.fabHeight / 2),
        child: InkWell(
          key: const ValueKey('topics_new'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTopics.fabHeight / 2),
          child: Container(
            height: AppTopics.fabHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.s,
              children: [
                Icon(Icons.add_rounded, size: 22, color: tokens.onacc),
                Text(
                  label,
                  style: TextStyle(
                    color: tokens.onacc,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
