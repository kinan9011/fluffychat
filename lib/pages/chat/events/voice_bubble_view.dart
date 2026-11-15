// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/pages/chat/events/message_bubble.dart';
import 'package:material_ui/material_ui.dart';

/// Play button, 26 bars and the duration (DESIGN.md 7.8). [bars] are 0..1,
/// [progress] is 0..1. [seek] is an invisible control laid over the bars.
class VoiceBubbleView extends StatelessWidget {
  final bool playing;
  final double progress;
  final List<double> bars;
  final String duration;
  final bool outgoing;
  final VoidCallback? onPlayPause;
  final VoidCallback? onLongPress;
  final double? downloadProgress;
  final bool downloading;
  final Widget? seek;
  final Widget? trailing;
  final String? playTooltip;

  const VoiceBubbleView({
    required this.playing,
    required this.progress,
    required this.bars,
    required this.duration,
    required this.outgoing,
    this.onPlayPause,
    this.onLongPress,
    this.downloadProgress,
    this.downloading = false,
    this.seek,
    this.trailing,
    this.playTooltip,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = BubbleColors.of(tokens, outgoing: outgoing);
    final played = (progress.clamp(0.0, 1.0) * bars.length).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 9, 13, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Tooltip(
            message: playTooltip ?? '',
            child: GestureDetector(
              onTap: downloading ? null : onPlayPause,
              onLongPress: onLongPress,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentFill,
                ),
                child: downloading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onAccent,
                          value: downloadProgress,
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 27,
                        color: colors.onAccent,
                      ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: [
              SizedBox(
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 2,
                      children: [
                        for (final (i, bar) in bars.indexed)
                          Container(
                            width: 2.5,
                            height: 4 + 20 * bar.clamp(0.0, 1.0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: i < played
                                  ? colors.accent
                                  : colors.secondary.withValues(alpha: 0.55),
                            ),
                          ),
                      ],
                    ),
                    if (seek != null) Positioned.fill(child: seek!),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Text(
                    duration,
                    style: TextStyle(color: colors.secondary, fontSize: 11),
                  ),
                  ?trailing,
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
