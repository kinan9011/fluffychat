// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// What an indexed message is, as far as search filters care.
enum SearchKind { text, image, video, file, audio, voice, poll }

/// The "Type" filter of the search sheet.
enum SearchType {
  photos,
  videos,
  files,
  links,
  voice,
  polls;

  bool accepts(SearchKind kind, {required bool hasLink}) => switch (this) {
    photos => kind == SearchKind.image,
    videos => kind == SearchKind.video,
    files => kind == SearchKind.file || kind == SearchKind.audio,
    links => hasLink,
    voice => kind == SearchKind.voice,
    polls => kind == SearchKind.poll,
  };
}

const _voiceKey = 'org.matrix.msc3245.voice';

/// The kind of [event], or null when search does not cover it (locations,
/// stickers, calls, unknown message types).
SearchKind? searchKindOf(Event event) {
  if (event.type == PollEventContent.startType) return SearchKind.poll;
  if (event.type != EventTypes.Message) return null;
  final msgtype = event.content['msgtype'];
  return switch (msgtype) {
    MessageTypes.Text ||
    MessageTypes.Notice ||
    MessageTypes.Emote => SearchKind.text,
    MessageTypes.Image => SearchKind.image,
    MessageTypes.Video => SearchKind.video,
    MessageTypes.File => SearchKind.file,
    MessageTypes.Audio =>
      event.content.containsKey(_voiceKey)
          ? SearchKind.voice
          : SearchKind.audio,
    _ => null,
  };
}

extension SearchKindEventType on SearchKind {
  /// The event type the retention rule looks at.
  String get eventType =>
      this == SearchKind.poll ? PollEventContent.startType : EventTypes.Message;
}
