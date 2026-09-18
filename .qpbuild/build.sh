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
mkdir -p "$WORK/app/src/main/res/drawable-nodpi"
cp "$RELAY/assets/quick_print_logo_official.webp" "$WORK/app/src/main/res/drawable-nodpi/quick_print_logo_official.webp"

# Hotfix 1.3.1: corrige exclusivamente o bootstrap do usuário local.
# Se o banco abrir sem usuário ativo, cria o Proprietário antes de liberar a autenticação.
python3 - "$WORK" <<'PY'
from pathlib import Path
import re
import sys

work = Path(sys.argv[1])
vm = work / "app/src/main/java/br/com/quickprint/os/QuickPrintViewModel.kt"
text = vm.read_text(encoding="utf-8")

pattern = re.compile(r'(?m)^(\s*)val first = repository\.firstActiveUser\(\)\s*$')
match = pattern.search(text)
if not match:
    raise SystemExit("hotfix abortado: bootstrap de usuário não encontrado")

indent = match.group(1)
patched = (
    f"{indent}var first = repository.firstActiveUser()\n"
    f"{indent}if (first == null) {{\n"
    f"{indent}    repository.addUser(\"Proprietário\", UserRole.OWNER)\n"
    f"{indent}    first = repository.firstActiveUser()\n"
    f"{indent}}}"
)
text = text[:match.start()] + patched + text[match.end():]
vm.write_text(text, encoding="utf-8")

gradle = work / "app/build.gradle.kts"
g = gradle.read_text(encoding="utf-8")
g, n1 = re.subn(r'versionCode\s*=\s*4\b', 'versionCode = 5', g, count=1)
g, n2 = re.subn(r'versionName\s*=\s*"1\.3\.0"', 'versionName = "1.3.1"', g, count=1)
if n1 != 1 or n2 != 1:
    raise SystemExit("hotfix abortado: versão 1.3.0 esperada não encontrada")
gradle.write_text(g, encoding="utf-8")
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

# Stable Quick Print signing key
KEYSTORE="$TOOLS/quickprint-release.jks"
printf '%s' "$QP_RELEASE_KEYSTORE_B64" | base64 -d > "$KEYSTORE"
export QP_KEYSTORE_PATH="$KEYSTORE"
export QP_KEYSTORE_PASSWORD="$QP_RELEASE_KEYSTORE_PASSWORD"
export QP_KEY_ALIAS="${QP_RELEASE_KEY_ALIAS:-quickprint}"
export QP_KEY_PASSWORD="$QP_RELEASE_KEY_PASSWORD"

cd "$WORK"

VERSION_CODE="$(sed -n 's/.*versionCode = \([0-9][0-9]*\).*/\1/p' app/build.gradle.kts | head -1)"
VERSION_NAME="$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' app/build.gradle.kts | head -1)"
test -n "$VERSION_CODE"
test -n "$VERSION_NAME"

echo "=== UNIT TESTS ==="
gradle --no-daemon testDebugUnitTest

echo "=== ANDROID LINT ==="
gradle --no-daemon lintRelease

echo "=== SIGNED RELEASE APK ==="
gradle --no-daemon assembleRelease

APK_SOURCE="app/build/outputs/apk/release/app-release.apk"
APK_VERSIONED="QuickPrintOS-v${VERSION_NAME}.apk"
APK_LATEST="QuickPrintOS-latest.apk"

cp "$APK_SOURCE" "$PUBLIC/$APK_VERSIONED"
cp "$APK_SOURCE" "$PUBLIC/$APK_LATEST"

SHA256="$(sha256sum "$PUBLIC/$APK_LATEST" | awk '{print $1}')"
NOTES="${QP_RELEASE_NOTES:-Atualização do Quick Print OS.}"

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
    json.dump(payload, f, ensure_ascii=False)
PY

cat > "$PUBLIC/index.html" <<HTML
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
<p>v${VERSION_NAME} • build assinada</p>
<div class="bar"></div>
<p>Passou por testes unitários, Android Lint e compilação release.</p>
<p><a href="./${APK_VERSIONED}">Baixar APK ${VERSION_NAME}</a></p>
<p><small>Atualizações futuras são detectadas dentro do próprio aplicativo.</small></p>
</main>
</html>
HTML

echo "VERSION=$VERSION_NAME ($VERSION_CODE)"
echo "SHA256=$SHA256"
ls -lh "$PUBLIC/$APK_VERSIONED"
