/// Stacker — a debug-only network, crash, and memory inspector for Flutter,
/// usable from native Android, native iOS, and hybrid apps.
///
/// See the README for platform integration. The short version:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Stacker.init();
///   runApp(const MyApp());
/// }
/// ```
library;

// Public API surface.
export 'src/core/http_status.dart'
    show HttpStatus, HttpStatusClass, HttpStatusInfo;
export 'src/core/stacker_config.dart' show StackerConfig, ToastPolicy;
export 'src/data/models/api_record.dart'
    show ApiCallState, ApiRecord, CaptureOrigin;
export 'src/data/models/crash_record.dart'
    show CrashRecord, CrashSeverity, CrashSource;
export 'src/data/models/leak_record.dart'
    show LeakConfidence, LeakKind, LeakRecord;
export 'src/interceptors/stacker_dio_interceptor.dart'
    show StackerDioInterceptor;
export 'src/interceptors/stacker_http_client.dart' show StackerHttpClient;
export 'src/stacker.dart' show Stacker;
export 'src/presentation/screens/dashboard_screen.dart'
    show DashboardTab, StackerDashboard;
export 'src/presentation/widgets/stacker_overlay.dart' show StackerOverlay;

// Exported for advanced use: custom UI on top of the captured data, and
// substituting fakes in tests.
export 'src/data/repository/stacker_repository.dart'
    show InMemoryStackerRepository, StackerRepository;
export 'src/presentation/blocs/api_list/api_list_bloc.dart'
    show
        ApiListBloc,
        ApiListCleared,
        ApiListEvent,
        ApiListFilter,
        ApiListFilterChanged,
        ApiListSearchChanged,
        ApiListState,
        ApiListStatus,
        ApiListSubscriptionRequested,
        ApiListUpdated;
export 'src/presentation/blocs/crash_list/crash_list_bloc.dart'
    show
        CrashListBloc,
        CrashListCleared,
        CrashListEvent,
        CrashListFilter,
        CrashListFilterChanged,
        CrashListSearchChanged,
        CrashListState,
        CrashListStatus,
        CrashListSubscriptionRequested;
export 'src/presentation/blocs/leak_list/leak_list_bloc.dart'
    show
        LeakListBloc,
        LeakListCleared,
        LeakListEvent,
        LeakListFilter,
        LeakListFilterChanged,
        LeakListSearchChanged,
        LeakListState,
        LeakListStatus,
        LeakListSubscriptionRequested;
