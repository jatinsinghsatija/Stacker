#
# Podspec for the Stacker Flutter plugin's iOS implementation.
#
# This is consumed automatically by the Flutter tool when an app depends on
# `stacker_inspector` from pub.dev — a developer never references it directly and never
# adds a `pod 'stacker_inspector'` line themselves. `s.source` is intentionally a local
# path because CocoaPods resolves it through the symlink Flutter creates in
# the host app's `ios/.symlinks/plugins/`, not over the network.
#
# Run `pod lib lint stacker_inspector.podspec` from this directory to validate changes.
#
Pod::Spec.new do |s|
  s.name             = 'stacker_inspector'
  s.version          = '0.1.0'
  s.summary          = 'Debug-only network, crash and memory inspector for Flutter.'
  s.description      = <<-DESC
Stacker records API calls, crashes and memory leaks and shows them in a
Chucker-style dashboard. Capture, the dashboard launcher and all timers are
disabled in release builds.
                       DESC
  s.homepage         = 'https://github.com/YOUR_USERNAME/stacker'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Stacker' => 'YOUR_EMAIL' }
  s.source           = { :path => '.' }
  s.source_files     = 'stacker/Sources/stacker/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'

  # Flutter.framework does not contain an i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'

  # Declares which required-reason APIs this plugin uses, so apps embedding
  # Stacker satisfy Apple's privacy manifest requirement without adding
  # anything of their own. Stacker collects no data and performs no tracking.
  s.resource_bundles = { 'stacker_inspector_privacy' => ['stacker/Sources/stacker/PrivacyInfo.xcprivacy'] }
end
