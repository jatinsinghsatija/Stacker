#
# Podspec for NATIVE iOS apps.
#
# This is not the Flutter plugin podspec — that one lives at
# `ios/stacker.podspec` and is consumed automatically by the Flutter tool.
# This file is for a plain Xcode project with no Flutter code of its own: it
# vends the prebuilt XCFrameworks produced by `flutter build ios-framework`,
# so a native iOS developer needs neither the Flutter SDK nor a Flutter
# module checkout.
#
# The zip it points at is attached to the matching GitHub Release. It is large
# (~230 MB) because `Flutter.xcframework` contains the engine for both device
# and simulator; CocoaPods downloads it once and caches it.
#
# Validate a change with:
#   pod spec lint StackerInspector.podspec --allow-warnings
#
Pod::Spec.new do |s|
  s.name             = 'StackerInspector'
  s.version          = '0.1.0'
  s.summary          = 'Debug-only network, crash and memory inspector for native iOS.'
  s.description      = <<-DESC
Stacker records API calls, crashes and memory leaks and shows them in a
Chucker-style dashboard. This pod is for native iOS apps: it ships prebuilt
XCFrameworks, so no Flutter SDK is required on developer machines or CI.

Open the dashboard by shaking the device or tapping the floating bubble.
Capture is off until StackerAutoAttach.enable() is called, which you should
guard with #if DEBUG.
                       DESC
  s.homepage         = 'https://github.com/YOUR_USERNAME/stacker'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'StackerInspector' => 'YOUR_EMAIL' }

  s.platform              = :ios, '13.0'
  s.swift_version         = '5.0'
  s.requires_arc          = true

  # The release asset. `:http` with a .zip makes CocoaPods download, unpack
  # and cache it — the frameworks are never committed to git.
  s.source = {
    :http => 'https://github.com/YOUR_USERNAME/stacker/releases/download/v0.1.0/StackerInspector-iOS-XCFrameworks-0.1.0.zip'
  }

  # The Release frameworks are vendored for every host configuration,
  # including the host app's Debug builds.
  #
  # Debug and Release Flutter artifacts are not interchangeable: the Debug set
  # is a JIT engine (38 MB) plus a `kernel_blob.bin` Dart snapshot in
  # `flutter_assets` (55 MB), while the Release set is an AOT engine (8.8 MB)
  # with the Dart compiled into `App` and no kernel blob (140 KB of assets).
  # Mixing an engine with the wrong snapshot type fails at launch. Measured
  # from the actual build output, not assumed.
  #
  # Release is the right choice here because the dashboard is Stacker's own
  # code and is never hot-reloaded by the host developer. It also keeps the
  # download ~90 MB smaller. Stacker's debug gating comes from
  # StackerAutoAttach.enable(), not from which engine is linked, so nothing is
  # lost. See RELEASE.md if you need the Debug set for dashboard development.
  s.vendored_frameworks = [
    'Release/Flutter.xcframework',
    'Release/App.xcframework',
    'Release/FlutterPluginRegistrant.xcframework',
    'Release/stacker_inspector.xcframework'
  ]

  s.frameworks = 'UIKit', 'Foundation'

  # Stacker collects nothing and performs no tracking; declared so host apps
  # inherit a valid privacy manifest.
  s.resource_bundles = { 'StackerInspector_privacy' => ['PrivacyInfo.xcprivacy'] }
end
