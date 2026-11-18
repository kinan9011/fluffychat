// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/matrix_room_id.dart';
import 'package:flutter/foundation.dart';

enum ScannedKind { user, room, alias }

/// What a scanned code points at, rebuilt from its parts: what is shown to
/// the user and what is opened is [normalizedUrl], never the scanned text.
@immutable
class ScannedTarget {
  const ScannedTarget({
    required this.kind,
    required this.identifier,
    required this.via,
    required this.eventId,
  });

  final ScannedKind kind;

  /// `@user:server`, `!room:server` or `#alias:server`.
  final String identifier;
  final List<String> via;
  final String? eventId;

  String get normalizedUrl =>
      MatrixLinkPolicy.link(identifier, eventId: eventId, via: via);
}

/// What may be trusted about links and servers that come from other people.
abstract final class MatrixLinkPolicy {
  static const maxVia = 5;
  static const maxServerNameChars = 253 + 6;
  static const maxLength = 2048;
  static const maxQueryPairs = 50;

  static final _serverName = RegExp(
    r'^[A-Za-z0-9](?:[A-Za-z0-9\-]{0,61}[A-Za-z0-9])?'
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]{0,61}[A-Za-z0-9])?)*'
    r'(?::[0-9]{1,5})?$',
  );

  /// A server name as it may be used to join through: `host` or `host:port`,
  /// no path, no user info, no brackets, no spaces.
  static bool isServerName(String value) {
    if (value.length > maxServerNameChars || !_serverName.hasMatch(value)) {
      return false;
    }
    final colon = value.lastIndexOf(':');
    return colon < 0 || int.parse(value.substring(colon + 1)) <= 65535;
  }

  /// At most [maxVia] valid, distinct server names out of [via] (input order).
  static List<String> safeVia(Iterable<Object?> via) {
    final result = <String>[];
    for (final value in via.take(maxVia * 20)) {
      if (result.length >= maxVia) break;
      if (value is! String || !isServerName(value)) continue;
      if (!result.contains(value)) result.add(value);
    }
    return result;
  }

  static final _structural = RegExp(r'[%/?#&]');

  static String _escape(String body) => body.replaceAllMapped(
    _structural,
    (match) => Uri.encodeComponent(match[0]!),
  );

  /// A matrix.to link whose identifier, event id and servers cannot add path
  /// segments or parameters: what [parse] reads back is what was given.
  static String link(
    String identifier, {
    String? eventId,
    List<String> via = const [],
  }) {
    final event = eventId;
    final servers = via
        .map((server) => 'via=${Uri.encodeQueryComponent(server)}')
        .join('&');
    return '${AppConfig.inviteLinkPrefix}'
        '${identifier[0]}${_escape(identifier.substring(1))}'
        '${event == null ? '' : '/${event[0]}${_escape(event.substring(1))}'}'
        '${servers.isEmpty ? '' : '?$servers'}';
  }

  /// The link that invites to a space: its alias when that is a valid alias,
  /// else its room id, with the own server as the way in. Null when there is
  /// nothing valid to link to.
  static String? inviteLink({
    required String alias,
    required String roomId,
    required String via,
  }) {
    if (!isServerName(via)) return null;
    if (alias.isNotEmpty && _isAlias(alias)) return link(alias, via: [via]);
    return _isRoomId(roomId) ? link(roomId, via: [via]) : null;
  }

  static final _userId = RegExp(r'^@[A-Za-z0-9._=\-/+]{1,255}:(.+)$');
  static final _alias = RegExp(r'^#[A-Za-z0-9._=\-/+]{1,255}:(.+)$');
  static final _roomWithServer = RegExp(r'^![A-Za-z0-9._=\-+]{1,255}:(.+)$');
  static final _roomWithoutServer = RegExp(r'^![A-Za-z0-9_\-]{43}$');

  static bool _plain(String text) {
    for (final rune in text.runes) {
      if (rune < 0x21 || rune > 0x7E) return false;
    }
    return true;
  }

  static bool _isUserId(String id) {
    final match = _userId.firstMatch(id);
    return match != null && isServerName(match.group(1)!) && id.length <= 255;
  }

  static bool _isRoomId(String id) {
    if (!_plain(id) || !isMatrixRoomId(id) || id.length > 255) return false;
    if (_roomWithoutServer.hasMatch(id)) return true;
    final match = _roomWithServer.firstMatch(id);
    return match != null && isServerName(match.group(1)!);
  }

  static bool _isAlias(String id) {
    final match = _alias.firstMatch(id);
    return match != null && isServerName(match.group(1)!) && id.length <= 255;
  }

  /// The target of a scanned code or pasted link, or null when it is not a
  /// plain Matrix link: only `https://matrix.to/#/...`, `matrix:` URIs and
  /// the links of this app are accepted, as printable ASCII of at most
  /// [maxLength] characters.
  static ScannedTarget? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.length > maxLength || !_plain(text)) return null;
    final lower = text.toLowerCase();
    if (lower.startsWith(AppConfig.deepLinkPrefix.toLowerCase())) {
      return _fromFragment(text.substring(AppConfig.deepLinkPrefix.length));
    }
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() == 'matrix') return _fromMatrixUri(uri);
    if (uri.scheme.toLowerCase() != 'https') return null;
    if (uri.host.toLowerCase() != 'matrix.to' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !uri.fragment.startsWith('/')) {
      return null;
    }
    return _fromFragment(uri.fragment.substring(1));
  }

  static String? _decode(String part) {
    try {
      return Uri.decodeComponent(part);
    } catch (_) {
      return null;
    }
  }

  static List<String> _viaOf(String? query) {
    if (query == null || query.isEmpty) return const [];
    final values = <String>[];
    for (final pair in query.split('&').take(maxQueryPairs)) {
      final at = pair.indexOf('=');
      if (at < 0 || pair.substring(0, at) != 'via') continue;
      final value = _decode(pair.substring(at + 1));
      if (value != null) values.add(value);
    }
    return safeVia(values);
  }

  static ScannedTarget? _fromFragment(String fragment) {
    final split = fragment.indexOf('?');
    final path = split < 0 ? fragment : fragment.substring(0, split);
    final query = split < 0 ? null : fragment.substring(split + 1);
    final segments = path.split('/').map(_decode).toList();
    if (segments.isEmpty ||
        segments.length > 2 ||
        segments.any((segment) => segment == null || segment.isEmpty)) {
      return null;
    }
    return _build(
      segments.first!,
      segments.length == 2 ? segments[1] : null,
      query,
    );
  }

  static ScannedTarget? _fromMatrixUri(Uri uri) {
    if (uri.hasFragment || uri.userInfo.isNotEmpty) return null;
    final segments = uri.path.split('/').map(_decode).toList();
    if (segments.any((segment) => segment == null || segment.isEmpty)) {
      return null;
    }
    final kind = segments.firstOrNull;
    if (kind == null || segments.length < 2) return null;
    final sigil = switch (kind) {
      'u' => '@',
      'r' => '#',
      'roomid' => '!',
      _ => null,
    };
    if (sigil == null) return null;
    String? eventId;
    if (segments.length == 4) {
      if (segments[2] != 'e') return null;
      eventId = '\$${segments[3]}';
    } else if (segments.length != 2) {
      return null;
    }
    return _build(
      '$sigil${segments[1]}',
      eventId,
      uri.hasQuery ? uri.query : null,
    );
  }

  static ScannedTarget? _build(
    String identifier,
    String? eventId,
    String? query,
  ) {
    final kind = switch (identifier.isEmpty ? '' : identifier[0]) {
      '@' => _isUserId(identifier) ? ScannedKind.user : null,
      '#' => _isAlias(identifier) ? ScannedKind.alias : null,
      '!' => _isRoomId(identifier) ? ScannedKind.room : null,
      _ => null,
    };
    if (kind == null) return null;
    if (eventId != null &&
        (kind == ScannedKind.user || !isMatrixEventId(eventId))) {
      return null;
    }
    return ScannedTarget(
      kind: kind,
      identifier: identifier,
      via: _viaOf(query),
      eventId: eventId,
    );
  }
}
