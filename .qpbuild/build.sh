#!/usr/bin/env bash
set -euo pipefail

ROOT="$PWD"
RELAY="$ROOT/.qpbuild"
WORK="$ROOT/.qpbuild/workspace"
TOOLS="$ROOT/.qpbuild/toolchain"
PUBLIC="$ROOT/.qpbuild/public"

rm -rf "$WORK" "$PUBLIC"
mkdir -p "$WORK" "$TOOLS" "$PUBLIC"

# Quick Print OS 1.5 source relay.
# The private source stays outside this public relay repository.
# Render downloads the sealed base bundle plus short-lived private overlays.
python3 - "$WORK" <<'PY'
import urllib.request, json, base64, pathlib, sys

urls = [
    "https://hatchable.com/s/eyJwIjo0ODc2MCwiayI6InRtcFwvcXAxNFwvc291cmNlLWJ1bmRsZS5qc29uIn0.ac6c5cf18007eea391f67885f4e278a2e6860412cfddaf03d92703ffb6ffbe13",
    "https://hatchable.com/s/eyJwIjo0ODc2MCwiayI6InRtcFwvcXAxNFwvb3ZlcmxheS0wMS5qc29uIn0.1ba1fdec2b46eb38d5eed52b0739b9e350886a7332cc69d908e576285154dd65",
    "https://hatchable.com/s/eyJwIjo0ODc2MCwiayI6InRtcFwvcXAxNFwvb3ZlcmxheS0wMi5qc29uIn0.3dfaca016ff236448a259ab44159466c0198a10c1d2df48e67fb72c60a97a8c7",
    "https://hatchable-sites.s3.amazonaws.com/apps/48760/storage/tmp/qp15-release/overlay-1.json?X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIA4Q6T3U6ITJF7RFW5%2F20260918%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20260918T150053Z&X-Amz-SignedHeaders=host&X-Amz-Expires=3600&X-Amz-Signature=73010968724844a87f50d38d1656dceda2674e79665b77becbf162338e8b63d7",
    "https://hatchable-sites.s3.amazonaws.com/apps/48760/storage/tmp/qp15-release/overlay-2.json?X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIA4Q6T3U6ITJF7RFW5%2F20260918%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20260918T150058Z&X-Amz-SignedHeaders=host&X-Amz-Expires=3600&X-Amz-Signature=0ae5fd51e2d14a6f24ddabce841cef7fcf8c49054eb9e4b096ff447f6a895968",
    "https://hatchable-sites.s3.amazonaws.com/apps/48760/storage/tmp/qp15-release/overlay-3.json?X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIA4Q6T3U6ITJF7RFW5%2F20260918%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20260918T150102Z&X-Amz-SignedHeaders=host&X-Amz-Expires=3600&X-Amz-Signature=7cf7185776b4c20615cb3c9920b8652b868e103e2be2bc2a937382728dc2ef41"
]

root = pathlib.Path(sys.argv[1])
writes = 0
for url in urls:
    with urllib.request.urlopen(url, timeout=120) as response:
        entries = json.load(response)
    for entry in entries:
        path = root / entry["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        if entry["encoding"] == "base64":
            path.write_bytes(base64.b64decode(entry["content"]))
        else:
            path.write_text(entry["content"], encoding="utf-8")
        writes += 1

print("Quick Print 1.5 source writes:", writes)
PY

# JDK 17
if [ ! -x "$TOOLS/jdk/bin/java" ]; then
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

# Stable Quick Print signing key. Values remain Render secrets.
KEYSTORE="$TOOLS/quickprint-release.jks"
printf '%s' "$QP_RELEASE_KEYSTORE_B64" | base64 -d > "$KEYSTORE"
chmod 600 "$KEYSTORE"
export QP_KEYSTORE_PATH="$KEYSTORE"
export QP_KEYSTORE_PASSWORD="$QP_RELEASE_KEYSTORE_PASSWORD"
export QP_KEY_ALIAS="${QP_RELEASE_KEY_ALIAS:-quickprint}"
export QP_KEY_PASSWORD="$QP_RELEASE_KEY_PASSWORD"

cd "$WORK"

VERSION_CODE="$(sed -n 's/.*versionCode = \([0-9][0-9]*\).*/\1/p' app/build.gradle.kts | head -1)"
VERSION_NAME="$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' app/build.gradle.kts | head -1)"
test "$VERSION_CODE" = "6"
test "$VERSION_NAME" = "1.5.0"

echo "=== UNIT TESTS ==="
gradle --no-daemon testDebugUnitTest

echo "=== ANDROID LINT ==="
gradle --no-daemon lintRelease

echo "=== SIGNED RELEASE APK ==="
gradle --no-daemon assembleRelease

APK_SOURCE="app/build/outputs/apk/release/app-release.apk"
test -s "$APK_SOURCE"

AAPT="$ANDROID_HOME/build-tools/35.0.0/aapt"
APKSIGNER="$ANDROID_HOME/build-tools/35.0.0/apksigner"

echo "=== APK IDENTITY ==="
"$AAPT" dump badging "$APK_SOURCE" | head -8
"$AAPT" dump badging "$APK_SOURCE" | grep -q "package: name='br.com.quickprint.os' versionCode='6' versionName='1.5.0'"

echo "=== SIGNATURE VALIDATION ==="
"$APKSIGNER" verify --verbose --print-certs "$APK_SOURCE"
NEW_CERT="$("$APKSIGNER" verify --print-certs "$APK_SOURCE" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1)"
test -n "$NEW_CERT"

# Compare with the APK currently distributed before replacing it.
PREVIOUS_APK="$TOOLS/QuickPrintOS-previous.apk"
curl -L --fail --retry 3 -o "$PREVIOUS_APK" "https://quickprint-os-updates.onrender.com/QuickPrintOS-latest.apk"
OLD_CERT="$("$APKSIGNER" verify --print-certs "$PREVIOUS_APK" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1)"
test -n "$OLD_CERT"

echo "PREVIOUS_CERT_SHA256=$OLD_CERT"
echo "NEW_CERT_SHA256=$NEW_CERT"
if [ "$OLD_CERT" != "$NEW_CERT" ]; then
  echo "ERROR: release certificate does not match previous Quick Print APK" >&2
  exit 1
fi
echo "SIGNING_CERT_MATCH=YES"

APK_VERSIONED="QuickPrintOS-v${VERSION_NAME}.apk"
APK_LATEST="QuickPrintOS-latest.apk"

cp "$APK_SOURCE" "$PUBLIC/$APK_VERSIONED"
cp "$APK_SOURCE" "$PUBLIC/$APK_LATEST"

SHA256="$(sha256sum "$PUBLIC/$APK_LATEST" | awk '{print $1}')"
NOTES="${QP_RELEASE_NOTES:-Quick Print OS 1.5.0 — Connected Operations: entregas, motoboys, transportadoras, consultas públicas e integrações gratuitas/opcionais.}"

python3 - "$PUBLIC/latest.json" "$VERSION_CODE" "$VERSION_NAME" "$SHA256" "$NOTES" <<'PY'
import json, sys
path, code, name, sha, notes = sys.argv[1:]
payload = {
  "versionCode": int(code),
  "versionName": name,
  "apkUrl": "https://quickprint-os-updates.onrender.com/QuickPrintOS-latest.apk",
  "sha256": sha,
  "notes": notes
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
PY

cat > "$PUBLIC/index.html" <<HTML
<!doctype html>
<html lang="pt-BR">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Quick Print OS 1.5.0</title>
<style>
body{font-family:system-ui,sans-serif;background:#f5f7fa;color:#142033;margin:0;padding:32px}
main{max-width:680px;margin:auto;background:#fff;border-radius:24px;padding:30px;box-shadow:0 12px 40px #14203318}
.bar{height:5px;background:linear-gradient(90deg,#159fe8 0 25%,#eb2f7d 25% 50%,#ffd21a 50% 75%,#111 75%);border-radius:8px;margin:22px 0}
a{display:inline-block;background:#159fe8;color:#fff;text-decoration:none;font-weight:700;padding:14px 20px;border-radius:14px}
small{color:#667085;word-break:break-all}
</style>
<main>
<h1>Quick Print OS</h1>
<p>v${VERSION_NAME} • release assinada</p>
<div class="bar"></div>
<p>Testes unitários, Android Lint, compilação release e compatibilidade do certificado de atualização validados.</p>
<p><a href="./${APK_VERSIONED}">Baixar APK ${VERSION_NAME}</a></p>
<p><small>SHA-256: ${SHA256}</small></p>
</main>
HTML

echo "VERSION=$VERSION_NAME ($VERSION_CODE)"
echo "SHA256=$SHA256"
echo "CERT_SHA256=$NEW_CERT"
ls -lh "$PUBLIC/$APK_VERSIONED"
