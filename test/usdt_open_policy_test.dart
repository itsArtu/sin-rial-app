import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'finance_workflow_test.dart' as fixtures;

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this.body);
  @override
  final int statusCode;
  final String body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  final HttpHeaders headers = _Headers();
  @override
  void write(Object? value) {}
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  int posts = 0;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _Request(_Response(404, '{}'));
  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    posts++;
    return _Request(
      _Response(
        200,
        '{"data":{"getBinanceP2PAverages":{"sellAverage":1000,"buyAverage":1010}}}',
      ),
    );
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Override extends HttpOverrides {
  final client = _Client();
  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'USDT fetches once per opening, never with BCV refresh or navigation',
    (tester) async {
      Map<String, dynamic>? nativeRate;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('rial/native_state'),
            (call) async => call.method == 'readRateState' && nativeRate != null
                ? jsonEncode(nativeRate)
                : null,
          );
      final previous = HttpOverrides.current;
      final override = _Override();
      HttpOverrides.global = override;
      addTearDown(() => HttpOverrides.global = previous);
      final dynamic app = await fixtures.fixture(tester);
      expect(override.client.posts, 1);
      expect(app.state['usdtRate'], 1005);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      nativeRate = {
        'rateLastAttemptMillis': stamp + 1000,
        'usdtLastRateMillis': 1,
        'usdtRate': 900,
      };
      await app.refreshRateIfNeeded(checkForUpdates: false);
      expect(app.state['usdtRate'], 1005);
      nativeRate = {
        'rateLastAttemptMillis': 1,
        'usdtLastRateMillis': stamp + 2000,
        'usdtRate': 1006,
        'usdtRateHistory': [
          {'date': '2026-11-02T12:00:00Z', 'value': 1006},
        ],
      };
      await app.refreshRateIfNeeded(checkForUpdates: false);
      expect(app.state['usdtRate'], 1006);
      expect(app.state['usdtRateHistory'], [
        {'date': '2026-11-02T12:00:00Z', 'value': 1006},
      ]);
      nativeRate = null;
      await app.refreshUsdtOnOpen();
      await app.refreshRate(checkForUpdates: false);
      app.setTab(2);
      await tester.pumpAndSettle();
      expect(override.client.posts, 1);
      app.didChangeAppLifecycleState(AppLifecycleState.inactive);
      app.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(override.client.posts, 1);
      app.didChangeAppLifecycleState(AppLifecycleState.paused);
      app.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(override.client.posts, 2);
      await tester.pump(const Duration(minutes: 31));
      await tester.pumpAndSettle();
      expect(override.client.posts, 2);
    },
  );
}
