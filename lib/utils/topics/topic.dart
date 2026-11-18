// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/matrix_room_id.dart';
import 'package:material_ui/material_ui.dart';

/// Content key a topic root event carries (a client convention; other apps
/// show the root as a normal message and the first line of its body).
const topicContentKey = 'im.fluffychat.topic';

/// The only icons a topic can ask for. Sender controlled text never picks an
/// icon by itself: it is looked up here, anything else falls back.
abstract class TopicIcons {
  static const fallback = 'tag';
  static const allowed = <String, IconData>{
    'tag': Icons.tag_rounded,
    'rocket_launch': Icons.rocket_launch_rounded,
    'palette': Icons.palette_rounded,
    'bug_report': Icons.bug_report_rounded,
    'translate': Icons.translate_rounded,
    'campaign': Icons.campaign_rounded,
    'forum': Icons.forum_rounded,
    'help': Icons.help_rounded,
    'event': Icons.event_rounded,
    'code': Icons.code_rounded,
    'lightbulb': Icons.lightbulb_rounded,
    'favorite': Icons.favorite_rounded,
  };

  static IconData of(String key) => allowed[key] ?? allowed[fallback]!;
}

@immutable
class Topic {
  const Topic({
    required this.rootEventId,
    required this.title,
    required this.icon,
    required this.replyCount,
    required this.lastActivity,
    required this.hue,
    this.lastSenderId = '',
    this.lastSender = '',
    this.lastPreview = '',
    this.unread = 0,
    this.mention = false,
  });

  final String rootEventId;
  final String title;
  final String icon;
  final int replyCount;
  final DateTime lastActivity;
  final double hue;
  final String lastSenderId;
  final String lastSender;
  final String lastPreview;
  final int unread;
  final bool mention;

  @override
  bool operator ==(Object other) =>
      other is Topic &&
      other.rootEventId == rootEventId &&
      other.title == title &&
      other.icon == icon &&
      other.replyCount == replyCount &&
      other.lastActivity == lastActivity &&
      other.hue == hue &&
      other.lastSenderId == lastSenderId &&
      other.lastSender == lastSender &&
      other.lastPreview == lastPreview &&
      other.unread == unread &&
      other.mention == mention;

  @override
  int get hashCode => Object.hash(
    rootEventId,
    title,
    icon,
    replyCount,
    lastActivity,
    hue,
    lastSenderId,
    lastSender,
    lastPreview,
    unread,
    mention,
  );

  Topic withUnread({required int unread, required bool mention}) => Topic(
    rootEventId: rootEventId,
    title: title,
    icon: icon,
    replyCount: replyCount,
    lastActivity: lastActivity,
    hue: hue,
    lastSenderId: lastSenderId,
    lastSender: lastSender,
    lastPreview: lastPreview,
    unread: unread,
    mention: mention,
  );
}

/// Builds topics from untrusted event content. Never throws.
abstract class TopicParser {
  static const titleMax = 60;
  static const previewMax = 80;
  static const senderMax = 40;
  static const replyCountMax = 1000000;
  static const maxRootsPerPage = 100;
  static const maxPages = 4;
  static const maxTopics = 200;

  static bool isEventId(Object? value) => isMatrixEventId(value);

  static String _firstLine(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');

  static Map<Object?, Object?>? _topicMap(Map<String, Object?> content) {
    final topic = content[topicContentKey];
    return topic is Map ? topic : null;
  }

  /// The title the root event carries, or the first line of its body.
  static String titleFrom(Map<String, Object?> content) {
    final custom = _topicMap(content)?['title'];
    final body = content['body'];
    final raw = custom is String && custom.trim().isNotEmpty
        ? custom
        : body is String
        ? body
        : '';
    return safeDisplayText(_firstLine(raw), maxGraphemes: titleMax);
  }

  static String iconFrom(Map<String, Object?> content) {
    final icon = _topicMap(content)?['icon'];
    return icon is String && TopicIcons.allowed.containsKey(icon)
        ? icon
        : TopicIcons.fallback;
  }

  /// A title typed by the user, made safe to send and to show.
  static String sanitizeTitle(String input) =>
      safeDisplayText(input, maxGraphemes: titleMax);

  /// Stable colour of a topic (0..359), from its root event id.
  static double hueFor(String eventId) {
    var hash = 0x811c9dc5;
    for (final unit in eventId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return (hash % 360).toDouble();
  }

  static Topic? fromRoot({
    required String eventId,
    required Map<String, Object?> content,
    required DateTime timestamp,
    Object? unsigned,
    String Function(String userId)? displayName,
  }) {
    try {
      if (!isEventId(eventId)) return null;
      final thread = _thread(unsigned);
      final count = thread?['count'];
      final latest = thread?['latest_event'];
      var lastSenderId = '';
      var lastSender = '';
      var lastPreview = '';
      var lastActivity = timestamp;
      if (latest is Map) {
        final sender = latest['sender'];
        final latestContent = latest['content'];
        final ts = latest['origin_server_ts'];
        if (ts is int) {
          lastActivity = DateTime.fromMillisecondsSinceEpoch(ts);
        }
        if (sender is String && sender.length <= 255) {
          lastSenderId = sender;
          lastSender = safeDisplayText(
            displayName?.call(sender) ?? sender,
            maxGraphemes: senderMax,
          );
        }
        final body = latestContent is Map ? latestContent['body'] : null;
        if (body is String) {
          lastPreview = safeDisplayText(body, maxGraphemes: previewMax);
        }
      }
      return Topic(
        rootEventId: eventId,
        title: titleFrom(content),
        icon: iconFrom(content),
        replyCount: count is int ? count.clamp(0, replyCountMax) : 0,
        lastActivity: lastActivity,
        hue: hueFor(eventId),
        lastSenderId: lastSenderId,
        lastSender: lastSender,
        lastPreview: lastPreview,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<Object?, Object?>? _thread(Object? unsigned) {
    if (unsigned is! Map) return null;
    final relations = unsigned['m.relations'];
    if (relations is! Map) return null;
    final thread = relations['m.thread'];
    return thread is Map ? thread : null;
  }
}
