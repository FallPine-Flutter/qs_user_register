part of '../qs_user_register.dart';

class _RegisterTask {
  /// System Funcs
  _RegisterTask({required Map<String, Object> input})
    : input = Map.unmodifiable(input);

  /// Custom Funcs
  bool matches({required Map<String, Object> input}) =>
      this.input.length == input.length &&
      input.entries.every((entry) => this.input[entry.key] == entry.value);

  void complete({required bool value}) {
    if (!firstResult.isCompleted) firstResult.complete(value);
  }

  Future<void> waitForRetry() {
    if (cancelled) return Future<void>.value();
    final completer = Completer<void>();
    retryWait = completer;
    retryTimer = Timer(const Duration(seconds: 5), () {
      retryTimer = null;
      retryWait = null;
      completer.complete();
    });
    return completer.future;
  }

  void cancel() {
    cancelled = true;
    requestToken?.cancel('注册任务已被替换或结束');
    retryTimer?.cancel();
    retryTimer = null;
    final wait = retryWait;
    retryWait = null;
    if (wait != null && !wait.isCompleted) wait.complete();
    complete(value: false);
  }

  /// Properties
  final Map<String, Object> input;
  final Completer<bool> firstResult = Completer<bool>();
  bool cancelled = false;
  CancelToken? requestToken;
  Timer? retryTimer;
  Completer<void>? retryWait;
}
