// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';

enum AttachmentType {
  gallery,
  file,
  richText,
  poll,
  checklist,
  location,
  photoCamera,
  videoCamera,
}

/// The entries of the bar. Location and the cameras are mobile only, as the
/// old attach menu had them.
List<AttachmentType> attachmentTypes({required bool mobile}) => [
  AttachmentType.gallery,
  AttachmentType.file,
  AttachmentType.richText,
  AttachmentType.poll,
  AttachmentType.checklist,
  if (mobile) ...[
    AttachmentType.location,
    AttachmentType.photoCamera,
    AttachmentType.videoCamera,
  ],
];

/// Attachment type bar under the composer (DESIGN 7.12, 9.7).
class AttachmentTypeBar extends StatelessWidget {
  const AttachmentTypeBar({
    required this.types,
    required this.onSelected,
    super.key,
  });

  final List<AttachmentType> types;
  final ValueChanged<AttachmentType> onSelected;

  static IconData _icon(AttachmentType type) => switch (type) {
    AttachmentType.gallery => Icons.photo_library_rounded,
    AttachmentType.file => Icons.description_rounded,
    AttachmentType.richText => Icons.article_rounded,
    AttachmentType.poll => Icons.ballot_rounded,
    AttachmentType.checklist => Icons.checklist_rounded,
    AttachmentType.location => Icons.location_on_rounded,
    AttachmentType.photoCamera => Icons.photo_camera_rounded,
    AttachmentType.videoCamera => Icons.videocam_rounded,
  };

  static String _label(L10n l10n, AttachmentType type) => switch (type) {
    AttachmentType.gallery => l10n.gallery,
    AttachmentType.file => l10n.attachFile,
    AttachmentType.richText => l10n.richText,
    AttachmentType.poll => l10n.attachPoll,
    AttachmentType.checklist => l10n.checkList,
    AttachmentType.location => l10n.attachLocation,
    AttachmentType.photoCamera => l10n.attachPhoto,
    AttachmentType.videoCamera => l10n.attachVideo,
  };

  static String _spoken(L10n l10n, AttachmentType type) => switch (type) {
    AttachmentType.photoCamera => l10n.takeAPhoto,
    AttachmentType.videoCamera => l10n.recordAVideo,
    _ => _label(l10n, type),
  };

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return Semantics(
      container: true,
      label: l10n.attachmentTypes,
      child: Container(
        height: AppChat.attachBarHeight,
        decoration: BoxDecoration(
          color: tokens.surf2,
          borderRadius: BorderRadius.circular(AppChat.attachBarRadius),
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(5),
          itemCount: types.length,
          separatorBuilder: (_, _) => const SizedBox(width: 2),
          itemBuilder: (context, index) {
            final type = types[index];
            return Semantics(
              button: true,
              label: _spoken(l10n, type),
              onTap: () => onSelected(type),
              excludeSemantics: true,
              child: InkResponse(
                key: ValueKey('attach_${type.name}'),
                onTap: () => onSelected(type),
                borderRadius: BorderRadius.circular(AppChat.attachItemRadius),
                containedInkWell: true,
                highlightShape: BoxShape.rectangle,
                child: Container(
                  width: AppChat.attachItemWidth,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      AppChat.attachItemRadius,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 3,
                    children: [
                      Icon(_icon(type), size: 23, color: tokens.fg),
                      Text(
                        _label(l10n, type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.fg,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
