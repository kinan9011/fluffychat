// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:odango/utils/chat/menu_placement.dart';

void main() {
  const screen = Size(400, 800);
  const safe = EdgeInsets.only(top: 40, bottom: 20);
  const bar = Size(300, 50);
  const menu = Size(230, 300);

  MenuPlacement place(
    Rect anchor, {
    bool outgoing = false,
    TextDirection direction = TextDirection.ltr,
    EdgeInsets safeArea = safe,
    Size menuSize = menu,
    Size screenSize = screen,
  }) => placeMessageMenu(
    anchor: anchor,
    screen: screenSize,
    safe: safeArea,
    barSize: bar,
    menuSize: menuSize,
    outgoing: outgoing,
    direction: direction,
  );

  void inside(
    MenuPlacement p, {
    EdgeInsets safeArea = safe,
    Size menuSize = menu,
  }) {
    for (final (offset, size) in [
      (p.barTopLeft, bar),
      (p.menuTopLeft, menuSize),
    ]) {
      expect(offset.dx.isFinite && offset.dy.isFinite, isTrue);
      expect(offset.dx, greaterThanOrEqualTo(safeArea.left));
      expect(offset.dy, greaterThanOrEqualTo(safeArea.top));
      expect(
        offset.dx + size.width,
        lessThanOrEqualTo(screen.width - safeArea.right),
      );
      expect(
        offset.dy + size.height,
        lessThanOrEqualTo(screen.height - safeArea.bottom),
      );
    }
  }

  test('mid screen: bar above, menu below, nothing overlaps the bubble', () {
    const anchor = Rect.fromLTWH(20, 300, 200, 60);
    final p = place(anchor);
    expect(p.menuAbove, isFalse);
    expect(p.barTopLeft.dy + bar.height, lessThanOrEqualTo(anchor.top));
    expect(p.menuTopLeft.dy, greaterThanOrEqualTo(anchor.bottom));
    inside(p);
  });

  test('a bubble at the top: the bar moves below it, the menu follows', () {
    const anchor = Rect.fromLTWH(20, 50, 200, 60);
    final p = place(anchor);
    expect(p.barTopLeft.dy, greaterThanOrEqualTo(anchor.bottom));
    expect(
      p.menuTopLeft.dy,
      greaterThanOrEqualTo(p.barTopLeft.dy + bar.height),
    );
    inside(p);
  });

  test('a bubble at the bottom: the menu goes above it', () {
    const anchor = Rect.fromLTWH(20, 700, 200, 60);
    final p = place(anchor);
    expect(p.menuAbove, isTrue);
    expect(p.menuTopLeft.dy + menu.height, lessThanOrEqualTo(anchor.top));
    inside(p);
  });

  test('outgoing bubbles align the end edges, incoming the start edges', () {
    const anchor = Rect.fromLTWH(100, 300, 280, 60);
    final outgoing = place(anchor, outgoing: true);
    expect(outgoing.barTopLeft.dx + bar.width, closeTo(anchor.right, 0.01));
    expect(outgoing.menuTopLeft.dx + menu.width, closeTo(anchor.right, 0.01));
    final incoming = place(const Rect.fromLTWH(30, 300, 200, 60));
    expect(incoming.barTopLeft.dx, closeTo(30, 0.01));
    expect(incoming.menuTopLeft.dx, closeTo(30, 0.01));
  });

  test('RTL mirrors the sides', () {
    const anchor = Rect.fromLTWH(30, 300, 200, 60);
    final p = place(anchor, outgoing: true, direction: TextDirection.rtl);
    expect(p.menuTopLeft.dx, closeTo(30, 0.01));
    final incoming = place(
      const Rect.fromLTWH(100, 300, 280, 60),
      direction: TextDirection.rtl,
    );
    expect(incoming.menuTopLeft.dx + menu.width, closeTo(380, 0.01));
  });

  test('a menu taller than the screen is clamped and stays on screen', () {
    const tall = Size(230, 900);
    final p = place(const Rect.fromLTWH(20, 400, 200, 60), menuSize: tall);
    expect(p.menuTopLeft.dy, greaterThanOrEqualTo(safe.top));
    expect(p.menuTopLeft.dx.isFinite, isTrue);
  });

  test('random anchors never give negative, NaN or off-screen offsets', () {
    final random = math.Random(7);
    for (var i = 0; i < 500; i++) {
      final w = 40 + random.nextDouble() * 340;
      final h = 20 + random.nextDouble() * 400;
      final anchor = Rect.fromLTWH(
        random.nextDouble() * (screen.width - w),
        random.nextDouble() * (screen.height - h),
        w,
        h,
      );
      final size = Size(230, 100 + random.nextDouble() * 400);
      final p = place(
        anchor,
        outgoing: random.nextBool(),
        direction: random.nextBool() ? TextDirection.ltr : TextDirection.rtl,
        menuSize: size,
      );
      inside(p, menuSize: size);
    }
  });

  test('bar and menu never overlap when both fit the screen (REV m17)', () {
    final random = math.Random(11);
    for (var i = 0; i < 500; i++) {
      final h = 20 + random.nextDouble() * 300;
      final anchor = Rect.fromLTWH(
        10,
        random.nextDouble() * (screen.height - h),
        200,
        h,
      );
      final size = Size(230, 100 + random.nextDouble() * 400);
      final p = place(anchor, menuSize: size);
      final barRect = p.barTopLeft & bar;
      final menuRect = p.menuTopLeft & size;
      expect(barRect.overlaps(menuRect), isFalse, reason: '$anchor $size');
    }
  });

  test('a bubble near the top and a tall menu: bar below, menu after it', () {
    const anchor = Rect.fromLTWH(20, 60, 200, 40);
    final p = place(anchor, menuSize: const Size(230, 620));
    final barRect = p.barTopLeft & bar;
    final menuRect = p.menuTopLeft & const Size(230, 620);
    expect(barRect.overlaps(menuRect), isFalse);
    inside(p, menuSize: const Size(230, 620));
  });

  test('the menu height follows the text scale', () {
    expect(menuHeightFor(4, TextScaler.noScaling), 4 * 46.0 + 12);
    expect(
      menuHeightFor(4, const TextScaler.linear(3)),
      greaterThan(menuHeightFor(4, TextScaler.noScaling)),
    );
  });
}
