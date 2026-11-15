// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/chat/bubble_shape.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const none = BorderRadiusDirectional.all(Radius.circular(20));

  test('no tail: 20 px everywhere', () {
    expect(bubbleRadius(outgoing: true, tail: false), none);
    expect(bubbleRadius(outgoing: false, tail: false), none);
  });

  test('outgoing tail is bottom end, incoming tail is bottom start', () {
    final outgoing = bubbleRadius(outgoing: true, tail: true);
    expect(outgoing.bottomEnd, const Radius.circular(6));
    expect(outgoing.bottomStart, const Radius.circular(20));
    final incoming = bubbleRadius(outgoing: false, tail: true);
    expect(incoming.bottomStart, const Radius.circular(6));
    expect(incoming.bottomEnd, const Radius.circular(20));
    expect(incoming.topStart, const Radius.circular(20));
    expect(incoming.topEnd, const Radius.circular(20));
  });

  test('the tail flips with the text direction', () {
    final incoming = bubbleRadius(outgoing: false, tail: true);
    expect(
      incoming.resolve(TextDirection.ltr).bottomLeft,
      const Radius.circular(6),
    );
    expect(
      incoming.resolve(TextDirection.rtl).bottomRight,
      const Radius.circular(6),
    );
    expect(
      incoming.resolve(TextDirection.rtl).bottomLeft,
      const Radius.circular(20),
    );
  });

  test('max width is 82 percent up to one and a half columns', () {
    expect(bubbleMaxWidth(300), closeTo(246, 0.001));
    expect(bubbleMaxWidth(5000), FluffyThemes.columnWidth * 1.5);
  });
}
