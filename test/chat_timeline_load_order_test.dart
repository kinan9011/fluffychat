// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a chat that was closed while its timeline loaded does not look up '
      'its context afterwards', () {
    final source = File('lib/pages/chat/chat.dart').readAsStringSync();
    final start = source.indexOf('Mark room as read on first visit');
    final end = source.indexOf('String? scrollUpBannerEventId', start);
    final body = source.substring(start, end);
    final lastRead = body.lastIndexOf('setReadMarker();');
    final guard = body.indexOf('if (!mounted) return;', lastRead);
    expect(lastRead, isNonNegative);
    expect(guard, isNonNegative);
    expect(body.indexOf('_scheduleRetention();'), greaterThan(guard));
    expect(body.indexOf('_loadTopics();'), greaterThan(guard));
  });
}
