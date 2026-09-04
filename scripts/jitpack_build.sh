#!/usr/bin/env bash
#
# Builds and installs the Stacker Android artifacts for JitPack.
#
# JitPack runs this from the repository root with `install:` in jitpack.yml,
# which means this script — not JitPack's default Gradle call — is responsible
# for putting artifacts into ~/.m2/repository for JitPack to harvest.
#
# Why a script instead of plain Gradle: the dashboard UI is compiled Dart, so
# the artifact has to be produced by `flutter build aar`. That command emits
# three things into build/host/outputs/repo as a Maven layout:
#
#   com.stacker.stacker_host:flutter_release / _debug / _profile   (Dart + plugins)
#   io.flutter:flutter_embedding_*                                 (engine)
#   io.flutter:arm64_v8a_* / armeabi_v7a_* / x86_64_*               (native libs)
#
# Those coordinates are what the consuming app resolves from JitPack.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.0}"
FLUTTER_HOME="${HOME}/flutter"

echo "==> Stacker JitPack build"
echo "    tag/version: ${VERSION:-<unset>}"

# ---------------------------------------------------------------------------
# 1. Flutter SDK
# ---------------------------------------------------------------------------
if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
  echo "==> Installing Flutter ${FLUTTER_VERSION}"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_HOME}"
fi
export PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

# Fail loudly and early if the toolchain is not usable, rather than emitting a
# half-built AAR that fails mysteriously at the consumer's Gradle sync.
flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true
flutter precache --android

# ---------------------------------------------------------------------------
# 2. Resolve Dart dependencies
# ---------------------------------------------------------------------------
echo "==> Resolving packages"
flutter pub get
(cd stacker_host && flutter pub get)

# ---------------------------------------------------------------------------
# 3. Build the AAR set
# ---------------------------------------------------------------------------
# All three build modes are produced so a consumer can use
# `debugImplementation` and `releaseImplementation` against matching variants.
# The debug variant is the one that carries the launcher-icon alias.
# A note on versioning, because it surprises people.
#
# `flutter build aar` always emits Maven version "1.0". It ignores
# --build-name for the artifact coordinate, and rewriting the generated
# .android/Flutter/build.gradle does not change the `stacker_*` artifacts
# either — they come from the plugin build, which Flutter re-stamps. This was
# verified by inspecting the emitted repo layout on a clean build.
#
# Consumers therefore always depend on `:1.0`, and select the *release* using
# the JitPack tag in the group id:
#
#     com.github.<user>.stacker:stacker_debug:1.0
#     └── the tag is baked into the JitPack build that produced this artifact
#
# JitPack builds one immutable artifact set per tag, so `v0.1.0` and `v0.2.0`
# are distinct builds even though both carry Maven version 1.0. Pinning a tag
# still pins a release; only the version *string* is fixed.
BUILD_NAME="${VERSION:-untagged}"
echo "==> Building tag ${BUILD_NAME} (artifacts are versioned 1.0 by Flutter)"

echo "==> Building AARs (this compiles the Dart dashboard)"
(cd stacker_host && flutter build aar --no-profile)

REPO="stacker_host/build/host/outputs/repo"
if [ ! -d "${REPO}" ]; then
  echo "!! flutter build aar produced no Maven repo at ${REPO}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Hand the artifacts to JitPack
# ---------------------------------------------------------------------------
# JitPack collects whatever is in the local Maven repository, so the generated
# layout is copied there wholesale. `cp -R` over an existing ~/.m2 is additive,
# which matters because the Flutter engine artifacts must land alongside ours.
echo "==> Installing artifacts into ~/.m2/repository"
mkdir -p "${HOME}/.m2/repository"
cp -R "${REPO}/." "${HOME}/.m2/repository/"

echo "==> Artifacts installed:"
find "${REPO}" -name "*.aar" -o -name "*.pom" | sed 's|^|    |' | sort

echo "==> Done."
