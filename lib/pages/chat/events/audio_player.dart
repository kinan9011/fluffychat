// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:fluffychat/pages/chat/events/voice_bubble_view.dart';
import 'package:fluffychat/utils/chat/waveform.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:path_provider/path_provider.dart';

import '../../../utils/matrix_sdk_extensions/event_extension.dart';
import '../../../widgets/fluffy_chat_app.dart';
import '../../../widgets/matrix.dart';

class AudioPlayerWidget extends StatefulWidget {
  static const int wavesCount = 40;
  final Color color;
  final Color linkColor;
  final double fontSize;
  final Event event;

  const AudioPlayerWidget(
    this.event, {
    required this.color,
    required this.linkColor,
    required this.fontSize,
    super.key,
  });

  @override
  AudioPlayerState createState() => AudioPlayerState();
}

enum AudioPlayerStatus { notDownloaded, downloading, downloaded }

class AudioPlayerState extends State<AudioPlayerWidget> {
  static const double buttonSize = 36;

  AudioPlayerStatus status = AudioPlayerStatus.notDownloaded;
  double? _downloadProgress;

  late final MatrixState matrix;
  List<int>? _waveform;
  String? _durationString;

  @override
  void dispose() {
    super.dispose();
    final audioPlayer = matrix.voiceMessageEventId.value != widget.event.eventId
        ? null
        : matrix.audioPlayer;
    if (audioPlayer != null) {
      if (audioPlayer.playing && !audioPlayer.isAtEndPosition) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(matrix.context).showMaterialBanner(
            MaterialBanner(
              padding: EdgeInsets.zero,
              leading: StreamBuilder(
                stream: audioPlayer.playerStateStream.asBroadcastStream(),
                builder: (context, _) => IconButton(
                  onPressed: () {
                    if (audioPlayer.isAtEndPosition) {
                      audioPlayer.seek(Duration.zero);
                    } else if (audioPlayer.playing) {
                      audioPlayer.pause();
                    } else {
                      audioPlayer.play();
                    }
                  },
                  icon: audioPlayer.playing && !audioPlayer.isAtEndPosition
                      ? const Icon(Icons.pause_outlined)
                      : const Icon(Icons.play_arrow_outlined),
                ),
              ),
              content: StreamBuilder(
                stream: audioPlayer.positionStream.asBroadcastStream(),
                builder: (context, _) => GestureDetector(
                  onTap: () => FluffyChatApp.router.go(
                    '/rooms/${widget.event.room.id}?event=${widget.event.eventId}',
                  ),
                  child: Text(
                    '🎙️ ${audioPlayer.position.minuteSecondString} / ${audioPlayer.duration?.minuteSecondString} - ${widget.event.senderFromMemoryOrFallback.calcDisplayname()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              actions: [
                IconButton(
                  onPressed: () {
                    audioPlayer.pause();
                    audioPlayer.dispose();
                    matrix.voiceMessageEventId.value = matrix.audioPlayer =
                        null;

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ScaffoldMessenger.of(
                        matrix.context,
                      ).clearMaterialBanners();
                    });
                  },
                  icon: const Icon(Icons.close_outlined),
                ),
              ],
            ),
          );
        });
        return;
      }
      audioPlayer.pause();
      audioPlayer.dispose();
      matrix.voiceMessageEventId.value = matrix.audioPlayer = null;
    }
  }

  Future<void> _onButtonTap() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(matrix.context).clearMaterialBanners();
    });
    final currentPlayer =
        matrix.voiceMessageEventId.value != widget.event.eventId
        ? null
        : matrix.audioPlayer;
    if (currentPlayer != null && !currentPlayer.isAtEndPosition) {
      if (currentPlayer.playing) {
        currentPlayer.pause();
      } else {
        currentPlayer.play();
      }
      return;
    }

    matrix.voiceMessageEventId.value = widget.event.eventId;
    matrix.audioPlayer
      ?..stop()
      ..dispose();
    File? file;
    MatrixFile? matrixFile;

    setState(() => status = AudioPlayerStatus.downloading);
    try {
      final fileSize = widget.event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');
      matrixFile = await widget.event.downloadAndDecryptAttachment(
        onDownloadProgress: fileSize != null && fileSize > 0
            ? (progress) {
                final progressPercentage = progress / fileSize;
                setState(() {
                  _downloadProgress = progressPercentage < 1
                      ? progressPercentage
                      : null;
                });
              }
            : null,
      );

      final attachmentUrl = widget.event.attachmentOrThumbnailMxcUrl();

      if (!kIsWeb && attachmentUrl != null) {
        final tempDir = await getTemporaryDirectory();
        final fileName = Uri.encodeComponent(attachmentUrl.pathSegments.last);
        file = File('${tempDir.path}/${fileName}_${matrixFile.name}');

        await file.writeAsBytes(matrixFile.bytes);

        if (Platform.isIOS &&
            matrixFile.mimeType.toLowerCase() == 'audio/ogg') {
          Logs().v('Convert ogg audio file for iOS...');
          final convertedFile = File('${file.path}.caf');
          if (await convertedFile.exists() == false) {
            await OggCafConverter().convertOggToCaf(
              input: file.path,
              output: convertedFile.path,
            );
          }
          file = convertedFile;
        }
      }

      setState(() {
        status = AudioPlayerStatus.downloaded;
      });
    } catch (e, s) {
      Logs().v('Could not download audio file', e, s);
      if (!mounted) rethrow;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
      rethrow;
    }
    if (!context.mounted) return;
    if (matrix.voiceMessageEventId.value != widget.event.eventId) return;

    final audioPlayer = matrix.audioPlayer = AudioPlayer();

    if (file != null) {
      audioPlayer.setFilePath(file.path);
    } else {
      await audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.dataFromBytes(matrixFile.bytes, mimeType: matrixFile.mimeType),
        ),
      );
    }
    if (!mounted) return;

    audioPlayer.play().onError(
      ErrorReporter(context, 'Unable to play audio message').onErrorCallback,
    );
  }

  Future<void> _toggleSpeed() async {
    final audioPlayer = matrix.audioPlayer;
    if (audioPlayer == null) return;
    switch (audioPlayer.speed) {
      case 1.0:
        await audioPlayer.setSpeed(1.25);
        break;
      case 1.25:
        await audioPlayer.setSpeed(1.5);
        break;
      case 1.5:
        await audioPlayer.setSpeed(2.0);
        break;
      case 2.0:
        await audioPlayer.setSpeed(0.5);
        break;
      case 0.5:
      default:
        await audioPlayer.setSpeed(1.0);
        break;
    }
    setState(() {});
  }

  List<int>? _getWaveform() => widget.event.content
      .tryGetMap<String, Object?>('org.matrix.msc1767.audio')
      ?.tryGetList<int>('waveform');

  @override
  void initState() {
    super.initState();
    matrix = Matrix.of(context);
    _waveform = _getWaveform();

    if (matrix.voiceMessageEventId.value == widget.event.eventId &&
        matrix.audioPlayer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(matrix.context).clearMaterialBanners();
      });
    }

    final durationInt = widget.event.content
        .tryGetMap<String, Object?>('info')
        ?.tryGet<int>('duration');
    if (durationInt != null) {
      final duration = Duration(milliseconds: durationInt);
      _durationString = duration.minuteSecondString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final waveform = _waveform;

    return ValueListenableBuilder(
      valueListenable: matrix.voiceMessageEventId,
      builder: (context, eventId, _) {
        final audioPlayer = eventId != widget.event.eventId
            ? null
            : matrix.audioPlayer;

        final fileDescription = widget.event.fileDescription;

        return StreamBuilder<Object>(
          stream: audioPlayer == null
              ? null
              : StreamGroup.merge([
                  audioPlayer.positionStream.asBroadcastStream(),
                  audioPlayer.playerStateStream.asBroadcastStream(),
                ]),
          builder: (context, _) {
            final maxPosition =
                audioPlayer?.duration?.inMilliseconds.toDouble() ?? 1.0;
            var currentPosition =
                audioPlayer?.position.inMilliseconds.toDouble() ?? 0.0;
            if (currentPosition > maxPosition) currentPosition = maxPosition;

            final statusText = audioPlayer == null
                ? _durationString ?? '00:00'
                : audioPlayer.position.minuteSecondString;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VoiceBubbleView(
                  playing:
                      audioPlayer?.playing == true &&
                      audioPlayer?.isAtEndPosition == false,
                  progress: maxPosition <= 0
                      ? 0
                      : currentPosition / maxPosition,
                  bars: resampleWaveform(waveform),
                  duration: statusText,
                  outgoing:
                      widget.event.senderId == widget.event.room.client.userID,
                  downloading: status == AudioPlayerStatus.downloading,
                  downloadProgress: _downloadProgress,
                  onPlayPause: _onButtonTap,
                  onLongPress: () => widget.event.saveFile(context),
                  trailing: audioPlayer == null
                      ? null
                      : InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _toggleSpeed,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              '${audioPlayer.speed}x',
                              style: TextStyle(
                                color: widget.color,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                  seek: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: widget.color,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      max: maxPosition,
                      value: currentPosition,
                      onChanged: (position) => audioPlayer == null
                          ? _onButtonTap()
                          : audioPlayer.seek(
                              Duration(milliseconds: position.round()),
                            ),
                    ),
                  ),
                ),
                if (fileDescription != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 13,
                      end: 13,
                      bottom: 4,
                    ),
                    child: Linkify(
                      text: fileDescription,
                      textScaleFactor: MediaQuery.textScalerOf(
                        context,
                      ).scale(1),
                      style: TextStyle(
                        color: widget.color,
                        fontSize: widget.fontSize,
                      ),
                      options: const LinkifyOptions(humanize: false),
                      linkStyle: TextStyle(
                        color: widget.linkColor,
                        fontSize: widget.fontSize,
                        decoration: TextDecoration.underline,
                        decorationColor: widget.linkColor,
                      ),
                      onOpen: (url) =>
                          UrlLauncher(context, url.url).launchUrl(),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

extension on AudioPlayer {
  bool get isAtEndPosition {
    final duration = this.duration;
    if (duration == null) return true;
    return position >= duration;
  }
}

extension on Duration {
  String get minuteSecondString =>
      '${inMinutes.toString().padLeft(2, '0')}:${(inSeconds % 60).toString().padLeft(2, '0')}';
}
