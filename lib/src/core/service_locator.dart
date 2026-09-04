import 'package:get_it/get_it.dart';

import '../data/repository/stacker_repository.dart';
import '../data/sources/stacker_platform.dart';
import '../domain/crash_reporter.dart';
import '../domain/leak_detector.dart';
import '../presentation/blocs/api_list/api_list_bloc.dart';
import '../presentation/blocs/crash_list/crash_list_bloc.dart';
import '../presentation/blocs/leak_list/leak_list_bloc.dart';
import 'id_generator.dart';
import 'stacker_config.dart';
import 'redactor.dart';

/// Dependency container for the library.
///
/// A dedicated [GetIt] instance is used rather than `GetIt.instance`, so
/// registering Stacker can never collide with the host app's own service
/// locator — the host may well be using GetIt too, and a shared instance would
/// mean our `StackerConfig` and theirs fight over the same namespace.
abstract final class StackerLocator {
  static final GetIt _getIt = GetIt.asNewInstance();

  /// The container. Exposed for advanced use and for tests.
  static GetIt get instance => _getIt;

  /// Whether [setUp] has completed.
  static bool get isReady => _getIt.isRegistered<StackerRepository>();

  /// Registers every dependency. Idempotent.
  ///
  /// Ordering matters: singletons that others depend on are registered first,
  /// and the BLoCs are registered as factories so each dashboard route gets a
  /// fresh instance with its own subscription.
  static Future<void> setUp(StackerConfig config) async {
    if (isReady) {
      await tearDown();
    }

    _getIt
      ..registerSingleton<StackerConfig>(config)
      ..registerSingleton<IdGenerator>(IdGenerator())
      ..registerSingleton<Redactor>(Redactor(config))
      ..registerSingleton<StackerPlatform>(StackerPlatform())
      ..registerSingleton<StackerRepository>(
        InMemoryStackerRepository(config),
        dispose: (repository) => repository.dispose(),
      )
      ..registerSingleton<CrashReporter>(
        CrashReporter(
          repository: _getIt<StackerRepository>(),
          idGenerator: _getIt<IdGenerator>(),
        ),
        dispose: (reporter) => reporter.uninstall(),
      )
      ..registerSingleton<LeakDetector>(
        LeakDetector(
          repository: _getIt<StackerRepository>(),
          config: config,
          idGenerator: _getIt<IdGenerator>(),
        ),
        dispose: (detector) => detector.stop(),
      )
      ..registerFactory<ApiListBloc>(
        () => ApiListBloc(repository: _getIt<StackerRepository>()),
      )
      ..registerFactory<CrashListBloc>(
        () => CrashListBloc(repository: _getIt<StackerRepository>()),
      )
      ..registerFactory<LeakListBloc>(
        () => LeakListBloc(repository: _getIt<StackerRepository>()),
      );
  }

  /// Resolves a registered dependency.
  static T get<T extends Object>() => _getIt<T>();

  /// Unregisters everything, running each `dispose` callback.
  static Future<void> tearDown() => _getIt.reset();
}
