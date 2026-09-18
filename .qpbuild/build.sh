# FINAL_V170_BUILD_TRIGGER
#!/usr/bin/env bash
set -euo pipefail

ROOT="$PWD"
RELAY="$ROOT/.qpbuild"
WORK="$ROOT/.qpbuild/workspace"
TOOLS="$ROOT/.qpbuild/toolchain"
PUBLIC="$ROOT/.qpbuild/public"

rm -rf "$WORK" "$PUBLIC"
mkdir -p "$WORK" "$TOOLS" "$PUBLIC"

# Quick Print OS 1.5.1 private base snapshot + encrypted 1.5.2 printing overlay.
# Source is encrypted at rest in this public relay; decryption key stays in Render secrets.
python3 "$RELAY/v151/decrypt.py" "$RELAY/v151" "$WORK" "$QP_BUILD_KEY_V151"

# Hotfix synced from quickprint-os-android feature/v1.5.1-connected-operations.
# Remove the constructor overload ambiguity discovered by the signed build itself.
python3 - "$WORK/app/src/main/java/br/com/quickprint/os/delivery/DeliveryRepository.kt" <<'PY'
from pathlib import Path
import re, sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    "class DeliveryRepository private constructor(",
    "class DeliveryRepository internal constructor(",
    1,
)
text = text.replace(
    "    private val gson: Gson,\n    private val postalCodeProvider",
    "    private val gson: Gson = Gson(),\n    private val postalCodeProvider",
    1,
)
pattern = re.compile(
    r"\n    internal constructor\(\n"
    r"        dao: DeliveryDao,[\s\S]*?"
    r"\n    \)\n\n    val deliveries:"
)
text, count = pattern.subn("\n\n    val deliveries:", text, count=1)
if count != 1:
    raise SystemExit("DeliveryRepository constructor hotfix did not match exactly once")
path.write_text(text, encoding="utf-8")
PY

# Apply only the Quick Print OS 1.5.2 printing changes.
# Overlay files remain encrypted in the relay; key stays in Render secrets.
python3 "$RELAY/v152/decrypt_overlay.py" "$RELAY/v152" "$WORK" "$QP_BUILD_KEY_V152"

# Keep the 1.5.2 Bluetooth runtime permission guard visible to Android Lint.
python3 - "$WORK/app/src/main/java/br/com/quickprint/os/integration/ThermalPrinter.kt" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "import android.annotation.SuppressLint" not in text:
    text = text.replace("import android.Manifest\n", "import android.Manifest\nimport android.annotation.SuppressLint\n", 1)
text = text.replace(
    "    fun pairedPrinters(context: Context): Result<List<BluetoothPrinterEndpoint>> = runCatching {",
    "    @SuppressLint(\"MissingPermission\")\n    fun pairedPrinters(context: Context): Result<List<BluetoothPrinterEndpoint>> = runCatching {",
    1,
)
text = text.replace(
    "    fun printTest(context: Context, address: String? = null): Result<Unit> = runCatching {",
    "    @SuppressLint(\"MissingPermission\")\n    fun printTest(context: Context, address: String? = null): Result<Unit> = runCatching {",
    1,
)
path.write_text(text, encoding="utf-8")
PY

# Apply Quick Print OS 1.6.0 Public Data Hub as a strictly additive overlay.
python3 "$RELAY/v160/decrypt_overlay.py" "$RELAY/v160" "$WORK" "$QP_BUILD_KEY_V160"

# Apply Quick Print OS 1.7.0 CRM 360 as an additive overlay over the validated 1.6 base.
python3 "$RELAY/v170/decrypt_overlay.py" "$RELAY/v170" "$WORK" "$QP_BUILD_KEY_V170"

mkdir -p "$WORK/app/src/main/res/drawable-nodpi"
cp "$RELAY/assets/quick_print_logo_official.webp" "$WORK/app/src/main/res/drawable-nodpi/quick_print_logo_official.webp"

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
test "$VERSION_CODE" = "10"
test "$VERSION_NAME" = "1.7.0"

echo "=== UNIT TESTS ==="
gradle --no-daemon testDebugUnitTest

echo "=== ANDROID LINT ==="
gradle --no-daemon lintRelease

echo "=== SIGNED RELEASE APK ==="
gradle --no-daemon assembleRelease
gradle --no-daemon validateSigningRelease

echo "=== ROOM SCHEMA ==="
test -s "app/schemas/br.com.quickprint.os.data.QuickPrintDatabase/6.json"
grep -Fq '"version": 6' "app/schemas/br.com.quickprint.os.data.QuickPrintDatabase/6.json"

APK_SOURCE="app/build/outputs/apk/release/app-release.apk"
test -s "$APK_SOURCE"

AAPT="$ANDROID_HOME/build-tools/35.0.0/aapt"
APKSIGNER="$ANDROID_HOME/build-tools/35.0.0/apksigner"

echo "=== APK IDENTITY ==="
BADGING="$("$AAPT" dump badging "$APK_SOURCE")"
printf '%s\n' "$BADGING" | sed -n '1,8p'
printf '%s\n' "$BADGING" | grep -Fq "package: name='br.com.quickprint.os' versionCode='10' versionName='1.7.0'"

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
NOTES="${QP_RELEASE_NOTES:-Quick Print OS 1.7.0 — CRM 360 & Customer Intelligence: Customer 360, leads, oportunidades, funil, agenda, follow-ups, RFM, reativação, deduplicação e vCard com migração Room 5→6 não destrutiva.}"

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
<title>Quick Print OS 1.7.0</title>
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
