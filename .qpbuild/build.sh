#!/usr/bin/env bash
set -euo pipefail

ROOT="$PWD"
RELAY="$ROOT/.qpbuild"
WORK="$ROOT/.qpbuild/workspace"
TOOLS="$ROOT/.qpbuild/toolchain"
PUBLIC="$ROOT/.qpbuild/public"

rm -rf "$WORK" "$PUBLIC"
mkdir -p "$WORK" "$TOOLS" "$PUBLIC"

python3 "$RELAY/decrypt.py" "$RELAY" "$WORK" "$QP_BUILD_KEY"

# JDK 17
if [ ! -x "$TOOLS/jdk/bin/java" ]; then
  echo "Downloading JDK 17..."
  curl -L --fail --retry 3 -o "$TOOLS/jdk.tar.gz" "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
  rm -rf "$TOOLS/jdk-tmp" "$TOOLS/jdk"
  mkdir -p "$TOOLS/jdk-tmp"
  tar -xzf "$TOOLS/jdk.tar.gz" -C "$TOOLS/jdk-tmp"
  mv "$TOOLS"/jdk-tmp/* "$TOOLS/jdk"
fi
export JAVA_HOME="$TOOLS/jdk"
export PATH="$JAVA_HOME/bin:$PATH"

# Gradle 8.10.2
if [ ! -x "$TOOLS/gradle/bin/gradle" ]; then
  echo "Downloading Gradle..."
  curl -L --fail --retry 3 -o "$TOOLS/gradle.zip" "https://services.gradle.org/distributions/gradle-8.10.2-bin.zip"
  rm -rf "$TOOLS/gradle-tmp" "$TOOLS/gradle"
  mkdir -p "$TOOLS/gradle-tmp"
  unzip -q "$TOOLS/gradle.zip" -d "$TOOLS/gradle-tmp"
  mv "$TOOLS"/gradle-tmp/gradle-8.10.2 "$TOOLS/gradle"
fi
export PATH="$TOOLS/gradle/bin:$PATH"

# Android SDK
export ANDROID_HOME="$TOOLS/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "Downloading Android command line tools..."
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  curl -L --fail --retry 3 -o "$TOOLS/android-tools.zip" "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest" "$TOOLS/android-unzip"
  mkdir -p "$TOOLS/android-unzip"
  unzip -q "$TOOLS/android-tools.zip" -d "$TOOLS/android-unzip"
  mv "$TOOLS/android-unzip/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
fi
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

yes | sdkmanager --licenses >/dev/null || true
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"

cd "$WORK"

echo "=== UNIT TESTS ==="
gradle --no-daemon testDebugUnitTest

echo "=== ANDROID LINT ==="
gradle --no-daemon lintDebug

echo "=== APK BUILD ==="
gradle --no-daemon assembleDebug

cp app/build/outputs/apk/debug/app-debug.apk "$PUBLIC/QuickPrintOS-v1.0.0-debug.apk"

cat > "$PUBLIC/index.html" <<'HTML'
<!doctype html>
<html lang="pt-BR">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Quick Print OS — APK</title>
<style>
body{font-family:system-ui,sans-serif;background:#f5f7fa;color:#142033;margin:0;padding:32px}
main{max-width:620px;margin:auto;background:#fff;border-radius:24px;padding:30px;box-shadow:0 12px 40px #14203318}
.bar{height:5px;background:linear-gradient(90deg,#159fe8 0 25%,#eb2f7d 25% 50%,#ffd21a 50% 75%,#111 75%);border-radius:8px;margin:22px 0}
a{display:inline-block;background:#159fe8;color:#fff;text-decoration:none;font-weight:700;padding:14px 20px;border-radius:14px}
small{color:#667085}
</style>
<main>
<h1>Quick Print OS</h1>
<p>v1.0.0 • APK interno de teste</p>
<div class="bar"></div>
<p>Build que passou por testes unitários, Android Lint e compilação do APK.</p>
<p><a href="./QuickPrintOS-v1.0.0-debug.apk">Baixar APK</a></p>
<p><small>Pacote: br.com.quickprint.os</small></p>
</main>
</html>
HTML

ls -lh "$PUBLIC/QuickPrintOS-v1.0.0-debug.apk"
