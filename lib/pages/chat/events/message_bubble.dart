// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/utils/appearance/chat_appearance_scope.dart';
import 'package:odango/utils/chat/bubble_shape.dart';

enum BubbleKind { normal, error, undecryptable, deleted }

BubbleKind bubbleKind(Event displayEvent, {required bool own}) {
  if (displayEvent.redacted) return BubbleKind.deleted;
  if (displayEvent.type == EventTypes.Encrypted &&
      displayEvent.messageType == MessageTypes.BadEncrypted) {
    return BubbleKind.undecryptable;
  }
  if (own && displayEvent.status.isError) return BubbleKind.error;
  return BubbleKind.normal;
}

/// Colours of whatever sits inside a bubble.
class BubbleColors {
  final Color fill;
  final Color text;
  final Color secondary;
  final Color link;
  final Color accent;
  final Color onAccent;
  final Color accentFill;

  const BubbleColors({
    required this.fill,
    required this.text,
    required this.secondary,
    required this.link,
    required this.accent,
    required this.onAccent,
    required this.accentFill,
  });

  factory BubbleColors.of(
    AppTokens tokens, {
    required bool outgoing,
    BubbleKind kind = BubbleKind.normal,
  }) {
    if (kind == BubbleKind.error) {
      return BubbleColors(
        fill: tokens.red,
        text: tokens.onRed,
        secondary: tokens.onRed,
        link: tokens.onRed,
        accent: tokens.onRed,
        onAccent: tokens.red,
        accentFill: tokens.onRed,
      );
    }
    if (outgoing) {
      return BubbleColors(
        fill: tokens.outS,
        text: tokens.outFg,
        secondary: tokens.outMut,
        link: tokens.outFg,
        accent: tokens.outFg,
        onAccent: tokens.outS,
        accentFill: tokens.outFg.withValues(alpha: 0.92),
      );
    }
    return BubbleColors(
      fill: tokens.surf,
      text: tokens.fg,
      secondary: tokens.mut,
      link: tokens.acc,
      accent: tokens.acc,
      onAccent: tokens.onacc,
      accentFill: tokens.acc,
    );
  }
}

/// The bubble surface (DESIGN.md 7.5): solid fill, tail on the last bubble of
/// a run, a 2 px ring for mentions and undecryptable messages.
class MessageBubble extends StatelessWidget {
  final BubbleKind kind;
  final bool outgoing;
  final bool tail;
  final bool mention;
  final bool transparent;
  final double? maxWidth;
  final Widget child;

  const MessageBubble({
    required this.kind,
    required this.outgoing,
    required this.tail,
    required this.child,
    this.mention = false,
    this.transparent = false,
    this.maxWidth,
    super.key,
  });

  @visibleForTesting
  Color? ringColor(AppTokens tokens) => switch (kind) {
    BubbleKind.undecryptable => tokens.warn,
    _ => mention && !outgoing ? tokens.acc : null,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = BubbleColors.of(tokens, outgoing: outgoing, kind: kind);
    final radius = bubbleRadius(
      outgoing: outgoing,
      tail: tail,
      corners: ChatAppearanceScope.cornersOf(context),
    );
    final ring = ringColor(tokens);
    final shape = radius.resolve(Directionality.of(context));
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            if (!transparent) ...AppElevation.bubble(tokens.shadow),
            if (ring != null) BoxShadow(color: ring, spreadRadius: 2),
          ],
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: ColoredBox(
            color: transparent ? Colors.transparent : colors.fill,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Content with the footer at the bottom end. The bubble is as wide as its
/// widest line, not as wide as it is allowed to be. Content that cannot report
/// intrinsic sizes (the map) gets a fixed [width] instead.
class BubbleBody extends StatelessWidget {
  final Widget content;
  final Widget footer;
  final double? width;

  const BubbleBody({
    required this.content,
    required this.footer,
    this.width,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 13,
            end: 13,
            bottom: 6,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: footer,
          ),
        ),
      ],
    );
    final fixed = width;
    if (fixed != null) return SizedBox(width: fixed, child: column);
    return IntrinsicWidth(child: column);
  }
}
