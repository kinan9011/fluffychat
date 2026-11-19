// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:odango/pages/chat/events/html_message.dart';

/// The bubble restyle (W04) must not widen what the HTML renderer accepts
/// from other people. Adding a tag here is a security decision: change this
/// list in the same commit and say why.
void main() {
  test('the allowed HTML tags are exactly the ones reviewed in W00', () {
    expect(HtmlMessage.allowedHtmlTags, const {
      'font',
      'del',
      's',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'blockquote',
      'p',
      'a',
      'ul',
      'ol',
      'sup',
      'sub',
      'li',
      'b',
      'i',
      'u',
      'strong',
      'em',
      'strike',
      'code',
      'hr',
      'br',
      'div',
      'table',
      'thead',
      'tbody',
      'tr',
      'th',
      'td',
      'caption',
      'pre',
      'span',
      'img',
      'details',
      'summary',
      'ruby',
      'rp',
      'rt',
      'html',
      'body',
    });
  });

  test('scripting, framing and form tags are not allowed', () {
    for (final tag in [
      'script',
      'iframe',
      'object',
      'embed',
      'form',
      'input',
      'style',
      'link',
      'meta',
      'svg',
      'math',
      'video',
      'audio',
    ]) {
      expect(HtmlMessage.allowedHtmlTags, isNot(contains(tag)), reason: tag);
    }
  });

  test('ignored tags stay minimal', () {
    expect(HtmlMessage.ignoredHtmlTags, const {'mx-reply'});
  });
}
