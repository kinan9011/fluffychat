// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_config.dart';
import 'package:odango/pages/chat/events/file_bubble_view.dart';
import 'package:odango/pages/chat/events/file_send_status_indicator.dart';
import 'package:odango/utils/chat/display_text.dart';
import 'package:odango/utils/file_description.dart';
import 'package:odango/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:odango/utils/url_launcher.dart';

class MessageDownloadContent extends StatelessWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;

  const MessageDownloadContent(
    this.event, {
    required this.textColor,
    required this.linkColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final filename = safeDisplayText(
      event.content.tryGet<String>('filename') ?? event.body,
      maxGraphemes: 255,
    );
    final filetype = (filename.contains('.')
        ? filename.split('.').last.toUpperCase()
        : event.content
                  .tryGetMap<String, Object?>('info')
                  ?.tryGet<String>('mimetype')
                  ?.toUpperCase() ??
              'UNKNOWN');
    final sizeString = event.sizeString ?? '?MB';
    final fileDescription = event.fileDescription;
    final fileSendingStatus = event.fileSendingStatus;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        FileBubbleView(
          filename: filename,
          meta: '$sizeString · $filetype',
          outgoing: event.senderId == event.room.client.userID,
          leading: fileSendingStatus == null
              ? null
              : FileSendStatusIndicator(fileSendingStatus: fileSendingStatus),
          onTap: () => event.saveFile(context),
        ),
        if (fileDescription != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 13.0,
              vertical: 4.0,
            ),
            child: Linkify(
              text: fileDescription,
              textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
              style: TextStyle(
                color: textColor,
                fontSize: AppConfig.messageFontSize,
              ),
              options: const LinkifyOptions(humanize: false),
              linkStyle: TextStyle(
                color: linkColor,
                fontSize: AppConfig.messageFontSize,
                decoration: TextDecoration.underline,
                decorationColor: linkColor,
              ),
              onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
            ),
          ),
        ],
      ],
    );
  }
}
