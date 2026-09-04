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
  s.version          = '0.2.0'
  s.summary          = 'Debug-only network, crash and memory inspector for native iOS.'
  s.description      = <<-DESC
Stacker records API calls, crashes and memory leaks and shows them in a
Chucker-style dashboard. This pod is for native iOS apps: it ships prebuilt
XCFrameworks, so no Flutter SDK is required on developer machines or CI.

Open the dashboard by shaking the device or tapping the floating bubble.
Capture is off until StackerAutoAttach.enable() is called, which you should
guard with #if DEBUG.
                       DESC
  s.homepage         = 'https://github.com/jatinsinghsatija/Stacker'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Jatin Singh Satija' => 'jatinsinghsatija@users.noreply.github.com' }

  s.platform              = :ios, '13.0'
  s.swift_version         = '5.0'
  s.requires_arc          = true

  # The release asset. `:http` with a .zip makes CocoaPods download, unpack
  # and cache it — the frameworks are never committed to git.
  s.source = {
    :http => 'https://github.com/jatinsinghsatija/Stacker/releases/download/v0.2.0/StackerInspector-iOS-XCFrameworks-0.2.0.zip'
  }

  # Frameworks are vended per configuration, and this split is load-bearing.
  #
  # `flutter build ios-framework` does NOT produce simulator Dart code in its
  # Release output — Apple's AOT compiler does not target the simulator.
  # Measured on the real build:
  #
  #   Release / ios-arm64                  App = 5.3 MB, 4 snapshot symbols
  #   Release / ios-arm64_x86_64-simulator App =  82 KB, 0 snapshot symbols
  #
  # Shipping Release for every configuration therefore black-screens on every
  # simulator with "Engine run configuration was invalid". The Debug (JIT) set
  # carries a kernel_blob.bin for both slices and runs on the simulator, so a
  # host's Debug configuration gets Debug frameworks.
  #
  # This also happens to be the right size trade-off: the Debug set is larger
  # (a 43 MB kernel blob) but only ever linked into debug builds, and Stacker
  # is a debug tool.
  s.subspec 'Debug' do |d|
    d.vendored_frameworks = [
      'Debug/Flutter.xcframework',
      'Debug/App.xcframework',
      'Debug/FlutterPluginRegistrant.xcframework',
      'Debug/stacker_inspector.xcframework'
    ]
  end

  s.subspec 'Release' do |r|
    r.vendored_frameworks = [
      'Release/Flutter.xcframework',
      'Release/App.xcframework',
      'Release/FlutterPluginRegistrant.xcframework',
      'Release/stacker_inspector.xcframework'
    ]
  end

  # Debug is the default subspec: Stacker is a debug tool, and a host that
  # pins `:configurations => ['Debug']` (as the README recommends) needs the
  # simulator-capable set.
  s.default_subspecs = 'Debug'

  s.frameworks = 'UIKit', 'Foundation'

  # Stacker collects nothing and performs no tracking; declared so host apps
  # inherit a valid privacy manifest.
  s.resource_bundles = { 'StackerInspector_privacy' => ['PrivacyInfo.xcprivacy'] }
end
