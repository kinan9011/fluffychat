#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Usage: scripts/test_share_intent.sh <adb serial of a throwaway emulator>
# Refuses any serial that is not emulator-* reporting qemu=1: the flutter test
# install can uninstall a differently signed FluffyChat and wipe its data.
# Proves that content:// shares from another app arrive as copies below
# cache/receive_sharing_intent/<uuid>/ and cannot reach other app files.
set -euo pipefail
DEVICE=${1:?usage: scripts/test_share_intent.sh <adb serial>}
APP=chat.fluffy.fluffychat
ADB="adb -s $DEVICE"

case "$DEVICE" in
emulator-*) ;;
*) echo "refusing: $DEVICE is not an emulator serial (emulator-*)" >&2; exit 2 ;;
esac
QEMU=$($ADB shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r' || true)
[ "$QEMU" = 1 ] || QEMU=$($ADB shell getprop ro.boot.qemu 2>/dev/null | tr -d '\r' || true)
[ "$QEMU" = 1 ] || { echo "refusing: $DEVICE does not report qemu=1" >&2; exit 2; }

integration_test/share_sender/build.sh
$ADB uninstall t197.evil >/dev/null 2>&1 || true
$ADB install integration_test/share_sender/out/sender.apk

LOG=$(mktemp)
flutter test integration_test/share_intent_test.dart -d "$DEVICE" >"$LOG" 2>&1 &
TEST_PID=$!
trap 'kill "$TEST_PID" 2>/dev/null || true; $ADB uninstall t197.evil >/dev/null 2>&1 || true; rm -f "$LOG"' EXIT

until grep -q T197_READY "$LOG"; do
    kill -0 "$TEST_PID" 2>/dev/null || { cat "$LOG"; exit 1; }
    sleep 2
done

share() {
    $ADB shell am start -n t197.evil/.SendActivity --es target "$APP" --es uri "$1" --ez grant "${2:-true}"
    sleep 3
}
for key in ok trav prefs abs rlo; do
    share "content://t197.evil/$key"
done
share "content://$APP.flutter.image_provider/cached_files/t197_own.txt" false

STATUS=0
wait "$TEST_PID" || STATUS=$?
cat "$LOG"
exit $STATUS
