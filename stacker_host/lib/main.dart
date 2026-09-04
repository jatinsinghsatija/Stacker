/// Dart side of the Stacker Flutter module.
///
/// This module exists purely so `flutter build aar` can package the Stacker
/// dashboard — the Flutter engine plus the AOT-compiled Dart — as ordinary
/// Maven artifacts that a native Android app can consume from JitPack.
///
/// Two entry points are exported:
///
///  * [stackerDashboardMain] — what `StackerActivity` runs. This is the one
///    that matters for native hosts; it is re-exported from the library so the
///    AAR and the pub package can never drift apart.
///  * [main] — only used by `flutter run` inside this module directory, for
///    working on the dashboard in isolation.
library;

import 'package:flutter/material.dart';
import 'package:stacker_inspector/stacker_inspector_dashboard_host.dart';

export 'package:stacker_inspector/stacker_inspector_dashboard_host.dart'
    show stackerDashboardMain;

/// Standalone harness for developing the dashboard on its own.
///
/// Not used by native hosts. `StackerActivity` starts the engine at
/// `stackerDashboardMain` instead, which is why that function — and not this
/// one — carries the `vm:entry-point` pragma.
@pragma('vm:entry-point')
Future<void> main() => stackerDashboardMain();

/// Kept so the module has a widget referenced from Dart, which stops the
/// analyzer flagging the Material import as unused in a bare module.
@visibleForTesting
const Widget stackerHostPlaceholder = SizedBox.shrink();
