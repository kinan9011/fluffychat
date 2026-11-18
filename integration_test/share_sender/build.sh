#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Builds the hostile sender test app into integration_test/share_sender/out/sender.apk
# with the Android SDK build tools only (no Gradle).
set -euo pipefail
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)
AJ=$(ls -d "$SDK"/platforms/android-* | sort -V | tail -1)/android.jar
rm -rf out && mkdir -p out/classes
"$BT/aapt2" link --manifest AndroidManifest.xml -I "$AJ" -o out/base.apk --min-sdk-version 24 --target-sdk-version 34
javac --release 17 -cp "$AJ" -d out/classes src/t197/evil/*.java
"$BT/d8" --lib "$AJ" --output out out/classes/t197/evil/*.class
python3 -I - <<'PY'
import zipfile
z = zipfile.ZipFile('out/base.apk', 'a')
z.write('out/classes.dex', 'classes.dex')
z.close()
PY
keytool -genkeypair -keystore out/debug.keystore -storepass android -keypass android \
    -alias k -keyalg RSA -keysize 2048 -validity 3650 -dname "CN=share-sender-test"
"$BT/apksigner" sign --ks out/debug.keystore --ks-pass pass:android --key-pass pass:android \
    --out out/sender.apk out/base.apk
