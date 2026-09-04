import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:stacker_inspector/stacker_inspector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One call. In a release build this is a no-op.
  await Stacker.init();

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stacker demo',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2962FF),
      ),
      // Adds the debug-only toast stack and the floating dashboard bubble.
      builder: (context, child) => StackerOverlay(child: child),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  late final Dio _dio;
  late final StackerHttpClient _httpClient;

  /// Held deliberately so the leak demo has something to retain.
  final List<Object> _leakedReferences = <Object>[];

  @override
  void initState() {
    super.initState();

    _dio = Dio(BaseOptions(baseUrl: 'https://httpbin.org'))
      // Added last so it sees the final headers.
      ..interceptors.add(StackerDioInterceptor());

    _httpClient = StackerHttpClient(inner: http.Client());

    // Watch this State for retention; the matching expectDisposed is below.
    Stacker.watchForLeaks(this, label: 'DemoPage');
  }

  @override
  void dispose() {
    Stacker.expectDisposed(this);
    _httpClient.close();
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stacker demo'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.dashboard_outlined),
            tooltip: 'Open the dashboard',
            onPressed: () => Stacker.openDashboard(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const _SectionHeader(
            title: 'Network capture',
            subtitle: 'Each call raises a toast and lands in the dashboard.',
          ),
          _ActionTile(
            icon: Icons.check_circle_outline,
            label: 'GET 200 — success',
            onTap: () => _dioGet('/get?source=stacker&demo=true'),
          ),
          _ActionTile(
            icon: Icons.post_add_rounded,
            label: 'POST 201 — with a JSON body and a bearer token',
            onTap: _dioPost,
          ),
          _ActionTile(
            icon: Icons.report_gmailerrorred_rounded,
            label: 'GET 404 — client error',
            onTap: () => _dioGet('/status/404'),
          ),
          _ActionTile(
            icon: Icons.dangerous_outlined,
            label: 'GET 500 — server error',
            onTap: () => _dioGet('/status/500'),
          ),
          _ActionTile(
            icon: Icons.lock_clock_rounded,
            label: 'GET 429 — rate limited',
            onTap: () => _dioGet('/status/429'),
          ),
          _ActionTile(
            icon: Icons.cloud_off_rounded,
            label: 'Transport failure — unresolvable host',
            onTap: _dioFail,
          ),
          _ActionTile(
            icon: Icons.http_rounded,
            label: 'GET via package:http instead of Dio',
            onTap: _plainHttpGet,
          ),
          const SizedBox(height: 8),
          const _SectionHeader(
            title: 'Crash capture',
            subtitle: 'Both handled and unhandled errors are recorded.',
          ),
          _ActionTile(
            icon: Icons.bug_report_outlined,
            label: 'Record a caught error (non-fatal)',
            onTap: _recordCaughtError,
          ),
          _ActionTile(
            icon: Icons.error_outline_rounded,
            label: 'Throw an uncaught async error',
            onTap: _throwUncaught,
          ),
          const SizedBox(height: 8),
          const _SectionHeader(
            title: 'Memory leak detection',
            subtitle:
                'Registers an object, declares it disposed, then keeps holding '
                'it — so it is provably retained.',
          ),
          _ActionTile(
            icon: Icons.link_rounded,
            label: 'Leak an object on purpose',
            onTap: _leakAnObject,
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Captured so far',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('${Stacker.apiRecords.length} API calls'),
                  Text('${Stacker.crashes.length} crashes'),
                  Text('${Stacker.leaks.length} leaks'),
                  const SizedBox(height: 6),
                  Text(
                    'Capture enabled: ${Stacker.isEnabled}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dioGet(String path) async {
    try {
      await _dio.get<dynamic>(path);
    } on DioException {
      // Already recorded by the interceptor; nothing to do here.
    }
    if (mounted) setState(() {});
  }

  Future<void> _dioPost() async {
    try {
      await _dio.post<dynamic>(
        '/post',
        data: <String, Object?>{
          'email': 'demo@example.com',
          // Redacted before storage — check the dashboard.
          'password': 'sup3rs3cret',
          'items': <int>[1, 2, 3],
        },
        options: Options(
          headers: <String, Object?>{
            // Also redacted.
            'Authorization': 'Bearer demo-token-abc123',
            'X-Request-Id': 'demo-42',
          },
        ),
      );
    } on DioException {
      // Recorded by the interceptor.
    }
    if (mounted) setState(() {});
  }

  Future<void> _dioFail() async {
    try {
      await _dio.get<dynamic>(
        'https://this-host-does-not-exist.invalid/ping',
      );
    } on DioException {
      // Recorded as a transport failure.
    }
    if (mounted) setState(() {});
  }

  Future<void> _plainHttpGet() async {
    try {
      await _httpClient.get(
        Uri.parse('https://httpbin.org/uuid'),
        headers: <String, String>{'X-Api-Key': 'demo-key-should-be-redacted'},
      );
    } on Object {
      // Recorded by the client wrapper.
    }
    if (mounted) setState(() {});
  }

  void _recordCaughtError() {
    try {
      throw StateError('Checkout total went negative');
    } on StateError catch (error, stackTrace) {
      Stacker.recordError(
        error,
        stackTrace,
        context: 'Recomputing the cart total',
        metadata: <String, String>{'cartId': 'demo-cart-7'},
      );
    }
    setState(() {});
  }

  void _throwUncaught() {
    // Escapes into PlatformDispatcher.onError, which Stacker hooks.
    Future<void>.delayed(
      const Duration(milliseconds: 60),
      () => throw Exception('Uncaught async failure from the demo'),
    );
  }

  void _leakAnObject() {
    final victim = _LeakVictim(payload: List<int>.filled(64 * 1024, 7));
    Stacker.watchForLeaks(victim, label: 'deliberate demo leak');
    // Declare it disposed while still holding it — the detector will notice.
    Stacker.expectDisposed(victim);
    _leakedReferences.add(victim);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Object retained. It is reported in the Memory tab after the '
          'retention window elapses.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// An object the demo retains on purpose.
class _LeakVictim {
  _LeakVictim({required this.payload});

  final List<int> payload;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(label, style: const TextStyle(fontSize: 13)),
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: onTap,
      ),
    );
  }
}
