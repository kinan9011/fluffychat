// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'utils/golden.dart';
import 'utils/space_message_goldens.dart';

void main() => registerSpaceMessageGoldens(
  goldenVariants.where((variant) => !variant.rtl).toList(),
);
