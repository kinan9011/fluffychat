// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/chat_list/folder_store.dart';
import 'package:odango/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:odango/widgets/future_loading_dialog.dart';

Future<bool> deleteFolder(
  BuildContext context,
  Client client,
  UserFolder folder,
) async {
  final l10n = L10n.of(context);
  final confirmed = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(l10n.deleteFolder),
      content: Text(l10n.deleteFolderConfirm(folder.name)),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        AdaptiveDialogAction(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            l10n.delete,
            style: TextStyle(color: AppTokens.of(context).red),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final result = await showFutureLoadingDialog(
    context: context,
    future: () => FolderStore.save(client, [
      for (final other in FolderStore.of(client).folders)
        if (other.id != folder.id) other,
    ]),
  );
  return result.error == null;
}
