#!/usr/bin/env bash
#
# Builds and packages the native-iOS XCFramework bundle for a GitHub Release.
#
# Native iOS hosts consume Stacker as prebuilt binaries so they never need the
# Flutter SDK. This script produces the single .zip that `StackerInspector.podspec`
# downloads, laid out exactly as the podspec's `vendored_frameworks` paths
# expect.
#
# Run from the repository root:
#     ./scripts/build_ios_frameworks.sh 0.1.0
#
# Output:
#     dist/StackerInspector-iOS-XCFrameworks-<version>.zip
#     plus the sha256 to paste into the release notes.
set -euo pipefail

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
  echo "usage: $0 <version>    e.g. $0 0.1.0" >&2
  exit 1
fi
VERSION="${VERSION#v}"   # tolerate a leading "v"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [ ! -d stacker_host ]; then
  echo "!! stacker_host/ not found. Run from the repository root." >&2
  exit 1
fi

command -v flutter >/dev/null 2>&1 || {
  echo "!! flutter not on PATH. Install the Flutter SDK first." >&2
  exit 1
}

STAGE="${ROOT}/dist/stage"
OUT="${ROOT}/dist/StackerInspector-iOS-XCFrameworks-${VERSION}.zip"

echo "==> Cleaning previous output"
rm -rf "${STAGE}" "${OUT}"
mkdir -p "${STAGE}"

echo "==> Resolving packages"
flutter pub get
(cd stacker_host && flutter pub get)

# --no-codesign: the frameworks are signed by the *consuming* app at its own
# build time. Signing them here would embed this machine's identity and break
# every other developer's build.
echo "==> Building XCFrameworks (compiles the Dart dashboard to AOT)"
(cd stacker_host && flutter build ios-framework \
    --no-profile \
    --no-debug \
    --no-codesign \
    --output=build/ios-framework)

SRC="stacker_host/build/ios-framework/Release"
for fw in Flutter App FlutterPluginRegistrant stacker_inspector; do
  if [ ! -d "${SRC}/${fw}.xcframework" ]; then
    echo "!! Missing ${SRC}/${fw}.xcframework" >&2
    exit 1
  fi
done

echo "==> Staging the bundle"
# The podspec's vendored_frameworks paths are "Release/<name>.xcframework",
# so that directory name is part of the archive's contract.
mkdir -p "${STAGE}/Release"
cp -R "${SRC}/." "${STAGE}/Release/"

# CocoaPods resolves `s.license` and `s.resource_bundles` against the unpacked
# archive, so both files have to travel inside the zip.
cp LICENSE "${STAGE}/LICENSE"
cp ios/stacker/Sources/stacker/PrivacyInfo.xcprivacy "${STAGE}/PrivacyInfo.xcprivacy"

echo "==> Zipping"
(cd "${STAGE}" && zip -qry "${OUT}" .)
rm -rf "${STAGE}"

echo
echo "==> Done"
echo "    file:   ${OUT}"
echo "    size:   $(du -h "${OUT}" | cut -f1)"
echo "    sha256: $(shasum -a 256 "${OUT}" | cut -d' ' -f1)"
echo
echo "Next: attach this .zip to the GitHub Release tagged v${VERSION},"
echo "then confirm StackerInspector.podspec's s.source URL matches that tag."
