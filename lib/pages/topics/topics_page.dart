// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/pages/topics/topic_create_sheet.dart';
import 'package:fluffychat/pages/topics/topics_view.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:fluffychat/utils/topics/topic.dart';
import 'package:fluffychat/utils/topics/topics_model.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class TopicsPage extends StatefulWidget {
  const TopicsPage({required this.roomId, super.key});

  final String roomId;

  @override
  State<TopicsPage> createState() => TopicsController();
}

class TopicsController extends State<TopicsPage> {
  TopicsModel? model;
  Timeline? _timeline;
  var supported = true;

  Room? get room => Matrix.of(context).client.getRoomById(widget.roomId);

  bool get canCreate => room?.canSendDefaultMessages ?? false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final matrix = Matrix.of(context);
    final room = this.room;
    if (room == null) return;
    final capabilities = await matrix.serverCapabilities.load(room.client);
    if (!mounted) return;
    if (!capabilities.supports(ServerFeature.threadNotifications)) {
      return setState(() => supported = false);
    }
    final model = this.model = TopicsModel(room);
    setState(() {});
    try {
      final timeline = await room.getTimeline(onUpdate: _onTimeline);
      if (!mounted || this.model != model) {
        timeline.cancelSubscriptions();
        return;
      }
      _timeline = timeline;
    } catch (_) {
      Logs().w('[Topics] could not read the timeline');
    }
    await refresh();
  }

  void _onTimeline() {
    if (mounted) unawaited(refresh());
  }

  Future<void> refresh({bool force = false}) async {
    final model = this.model;
    if (model == null) return;
    await model.load(_timeline?.events ?? const [], force: force);
  }

  void retry() {
    model?.status.value = TopicsStatus.loading;
    unawaited(refresh(force: true));
  }

  void openGeneral() => context.go('/rooms/${widget.roomId}');

  void openTopic(Topic topic) => context.go(
    '/rooms/${widget.roomId}?thread=${Uri.encodeQueryComponent(topic.rootEventId)}',
  );

  Future<void> newTopic() async {
    final room = this.room;
    if (room == null || !canCreate) return;
    final id = await showTopicCreateSheet(context, room);
    if (!mounted || id == null) return;
    await refresh();
    if (!mounted || !TopicParser.isEventId(id)) return;
    context.go(
      '/rooms/${widget.roomId}?thread=${Uri.encodeQueryComponent(id)}',
    );
  }

  @override
  void dispose() {
    _timeline?.cancelSubscriptions();
    model?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TopicsView(this);
}
