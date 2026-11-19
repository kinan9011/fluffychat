// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:odango/config/design_constants.dart';

/// The only gate for links the composer writes into a message.
///
/// Hosts must be plain ASCII: an internationalised name is refused, never
/// converted, so a lookalike (`exаmple.com` with a Cyrillic а) cannot be sent
/// and the user has to paste the punycode form (`xn--…`) on purpose. A link
/// that was accepted parses to itself again.
abstract class LinkPolicy {
  static const allowedSchemes = {'https', 'http', 'mailto', 'matrix'};

  static final _forbidden = RegExp(
    '[\\u0000-\\u0020\\u007f-\\u009f<>"\'\\\\`^{|}'
    '\\u200b-\\u200f\\u202a-\\u202e\\u2060-\\u2069\\ufeff]',
  );
  static final _hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');
  static final _hostPort = RegExp(r'^[^:/\s]+:\d{1,5}(/|$)');
  static final _mailbox = RegExp(r'^[^\s@]+@[^\s@]+$');
  static final _asciiHost = RegExp(r'^[a-zA-Z0-9._\-:]+$');

  static String _authority(String text) =>
      text.substring(text.indexOf('//') + 2).split(RegExp(r'[/?#]')).first;

  static Uri? parse(String input) {
    var text = input.trim();
    if (text.isEmpty || text.length > RichLimits.maxLinkUnits) return null;
    if (_forbidden.hasMatch(text)) return null;
    if (_hostPort.hasMatch(text) || !_hasScheme.hasMatch(text)) {
      text = 'https://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !allowedSchemes.contains(uri.scheme)) return null;
    switch (uri.scheme) {
      case 'http' || 'https':
        if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
        if (_authority(text).contains('%') || !_asciiHost.hasMatch(uri.host)) {
          return null;
        }
      case 'mailto':
        if (!_mailbox.hasMatch(uri.path) ||
            !_asciiHost.hasMatch(uri.path.split('@').last)) {
          return null;
        }
      case 'matrix':
        if (uri.path.isEmpty) return null;
    }
    return uri;
  }
}
