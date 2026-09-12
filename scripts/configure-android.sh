#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import pathlib
import re

kts = pathlib.Path('android/app/build.gradle.kts')
groovy = pathlib.Path('android/app/build.gradle')
marker = 'photo-atlas:configured'

LOADER = '''val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
}
'''

KTS_BLOCKS = '''
    signingConfigs {
        create("release") {
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
        }
    }

    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
'''

GROOVY_BLOCKS = '''
    signingConfigs {
        release {
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
        }
    }

    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
'''


if kts.exists():
    text = kts.read_text()
    if marker not in text:
        text = LOADER + '\n' + text
        match = re.search(r'^android \{', text, flags=re.MULTILINE)
        if match is None:
            raise SystemExit('android { block not found in build.gradle.kts')
        insert_at = match.end()
        text = text[:insert_at] + '\n' + KTS_BLOCKS + text[insert_at:]
        text = text.replace(
            'signingConfig = signingConfigs.getByName("debug")',
            'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
        )
        text = text.rstrip() + '\n// ' + marker + '\n'
        kts.write_text(text)
        print('configured build.gradle.kts')
    else:
        print('build.gradle.kts already configured')
elif groovy.exists():
    text = groovy.read_text()
    if marker not in text:
        text = LOADER.replace('java.util.Properties()', 'new Properties()').replace(
            'java.io.FileInputStream', 'new FileInputStream'
        ) + '\n' + text
        match = re.search(r'^android \{', text, flags=re.MULTILINE)
        if match is None:
            raise SystemExit('android { block not found in build.gradle')
        insert_at = match.end()
        text = text[:insert_at] + '\n' + GROOVY_BLOCKS + text[insert_at:]
        text = text.replace(
            'signingConfig signingConfigs.debug',
            "signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug",
        )
        text = text.rstrip() + '\n// ' + marker + '\n'
        groovy.write_text(text)
        print('configured build.gradle')
    else:
        print('build.gradle already configured')
else:
    raise SystemExit('no Android build.gradle(.kts) found: run the scaffold workflow first')

for manifest_path in [
    pathlib.Path('android/app/src/main/AndroidManifest.xml'),
    pathlib.Path('android/app/src/debug/AndroidManifest.xml'),
    pathlib.Path('android/app/src/profile/AndroidManifest.xml'),
]:
    if not manifest_path.exists():
        continue
    manifest = manifest_path.read_text()
    if manifest_path.name == 'AndroidManifest.xml' and 'src/main' in str(manifest_path):
        if 'android.permission.INTERNET' not in manifest:
            manifest = manifest.replace(
                '<application',
                '    <uses-permission android:name="android.permission.INTERNET"/>\n    <application',
                1,
            )
            manifest_path.write_text(manifest)
            print('added INTERNET permission to main manifest')
    else:
        cleaned = re.sub(r'\s*<uses-permission android:name="android.permission.INTERNET"\s*/>', '', manifest)
        if cleaned != manifest:
            manifest_path.write_text(cleaned)
            print(f'removed duplicate INTERNET permission from {manifest_path}')
PY

echo "Android configuration complete"
