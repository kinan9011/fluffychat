// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/pages/chat_list/chat_list.dart';
import 'package:odango/pages/chat_list/start_chat_fab.dart';

import 'chat_list_body.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !controller.scope.archived,
      onPopInvokedWithResult: (pop, _) {
        if (pop) return;
        if (controller.scope.archived) {
          controller.closeArchived();
          return;
        }
      },
      child: GestureDetector(
        onTap: FocusManager.instance.primaryFocus?.unfocus,
        excludeFromSemantics: true,
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          body: SafeArea(
            top: false,
            bottom: false,
            left: false,
            right: false,
            child: ChatListViewBody(controller),
          ),
          floatingActionButton: ValueListenableBuilder(
            valueListenable: controller.scrolledToTop,
            builder: (context, scrolledToTop, _) =>
                StartChatFab(extended: scrolledToTop),
          ),
        ),
      ),
    );
  }
}
