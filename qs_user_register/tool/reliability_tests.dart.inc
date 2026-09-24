import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:dio/io.dart';
import 'package:qs_ip_location/qs_ip_location_model.dart';
// END TEST IMPORTS

class Platform {
  static bool isIOS = true;
  static bool isAndroid = false;
}
class QsStorageTool {
  static bool registered = false;
  static int writes = 0;
  static Future<bool?> Function()? read;
  static Future<bool> Function()? write;
  static Future<bool?> getBool({required String key}) =>
      read?.call() ?? Future.value(registered);
  static Future<bool> setBool({required String key, required bool value}) {
    writes++;
    if (write != null) return write!();
    registered = value;
    return Future.value(true);
  }
}
class QsDeviceInfo {
  static Future<String> Function()? version;
  static Future<String> getAppVersion() => version?.call() ?? Future.value('1');
  static Future<String> getDeviceModel() async => 'model';
  static Future<String> getDeviceOSVersion() async => 'os';
  static String getDeviceType() => 'ios';
}
class QsAsaAttributionInfo {
  static Future<String?> Function()? token;
  static Future<String?> getAttributionToken() => token?.call() ?? Future.value('token');
}
class QsIpLocation {
  static Future<QsIpLocationModel?> Function()? location;
  static Future<QsIpLocationModel?> getIpLocation() => location?.call() ?? Future.value(null);
}
class Adapter implements HttpClientAdapter {
  int calls = 0;
  int cancellations = 0;
  final List<RequestOptions> requests = [];
  Future<ResponseBody> Function(int)? respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancelFuture) {
    requests.add(options);
    calls++;
    cancelFuture?.then((_) => cancellations++);
    return respond?.call(calls) ?? Future.value(body(code: 0));
  }
  @override
  void close({bool force = false}) {}
}
ResponseBody body({required int code}) => ResponseBody.fromString(
  '{"code":$code}', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

Future<bool> register({String user = 'a', String url = 'http://localhost/register', String tokenField = 'customToken'}) => QsUserRegister.register(
  apiUrl: url,
  apiParameterNameModel: QsUserRegisterApiParameterNameModel(
    userId: 'userId', fcmId: 'fcmId', appVersion: 'appVersion',
    deviceType: 'deviceType', deviceModel: 'deviceModel', deviceOSVersion: 'os',
    timezone: 'timezone', locale: 'locale', ipCountry: 'country', ipState: 'state',
    ipCity: 'city', ipAddress: 'ip', pushState: 'push', attributionToken: tokenField),
  aesSecretKey: '0123456789abcdef', aesIv: '0123456789abcdef', aesSctToken: 'sct',
  userId: user, fcmId: 'fcm', locale: 'en', pushState: true);

void main() {
  late Adapter adapter;
  setUp(() {
    QsUserRegister._activeTask = null;
    QsUserRegister._commitFuture = null;
    QsStorageTool.registered = false;
    QsStorageTool.writes = 0;
    QsStorageTool.read = null;
    QsStorageTool.write = null;
    QsDeviceInfo.version = null;
    QsAsaAttributionInfo.token = null;
    QsIpLocation.location = null;
    adapter = Adapter();
    QsUserRegister._dio.httpClientAdapter = adapter;
  });
  tearDown(() => QsUserRegister._activeTask?.cancel());

  test('same input shares first result and sends one request', () {
    fakeAsync((clock) {
      final a = register();
      final b = register();
      expect(identical(a, b), true);
      bool? result;
      a.then((value) => result = value);
      clock.elapse(Duration.zero);
      expect(result, true);
      expect(adapter.calls, 1);
      expect(QsStorageTool.writes, 1);
      expect(QsUserRegister._activeTask, null);
    });
  });
  test('failures retry exactly five seconds after completion', () {
    fakeAsync((clock) {
      adapter.respond = (n) async => body(code: n < 3 ? 1 : 0);
      register();
      clock.elapse(Duration.zero);
      expect(adapter.calls, 1);
      register();
      clock.elapse(Duration.zero);
      expect(adapter.calls, 1);
      clock.elapse(const Duration(milliseconds: 4999));
      expect(adapter.calls, 1);
      clock.elapse(const Duration(milliseconds: 1));
      expect(adapter.calls, 2);
      clock.elapse(const Duration(seconds: 5));
      expect(adapter.calls, 3);
      clock.elapse(const Duration(seconds: 20));
      expect(adapter.calls, 3);
      expect(QsUserRegister._activeTask, null);
    });
  });
  test('whole request deadline cancels transport then retries after five seconds', () {
    fakeAsync((clock) {
      adapter.respond = (_) => Completer<ResponseBody>().future;
      bool? result;
      register().then((v) => result = v);
      clock.elapse(Duration.zero);
      clock.elapse(const Duration(seconds: 29));
      expect(result, null);
      clock.elapse(const Duration(seconds: 1));
      expect(result, false);
      expect(adapter.cancellations, 1);
      clock.elapse(const Duration(seconds: 4));
      expect(adapter.calls, 1);
      clock.elapse(const Duration(seconds: 1));
      expect(adapter.calls, 2);
      QsUserRegister._activeTask!.cancel();
      clock.elapse(Duration.zero);
    });
  });
  test('replacement cancels old transport and ignores late success', () {
    fakeAsync((clock) {
      final oldResponse = Completer<ResponseBody>();
      adapter.respond = (n) => n == 1 ? oldResponse.future : Future.value(body(code: 0));
      bool? oldResult;
      register().then((v) => oldResult = v);
      clock.elapse(Duration.zero);
      register(user: 'b');
      clock.elapse(Duration.zero);
      expect(oldResult, false);
      expect(adapter.cancellations, 1);
      expect(adapter.calls, 2);
      oldResponse.complete(body(code: 0));
      clock.elapse(Duration.zero);
      expect(QsStorageTool.writes, 1);
      clock.elapse(const Duration(seconds: 40));
      expect(adapter.calls, 2);
    });
  });
  test('replacement cancels retry timer', () {
    fakeAsync((clock) {
      adapter.respond = (n) async => body(code: n == 1 ? 1 : 0);
      register();
      clock.elapse(Duration.zero);
      register(user: 'b');
      clock.elapse(Duration.zero);
      clock.elapse(const Duration(seconds: 20));
      expect(adapter.calls, 2);
      expect(QsStorageTool.writes, 1);
    });
  });
  test('preparation is parallel, times out and ignores replaced late result', () {
    fakeAsync((clock) {
      final location = Completer<QsIpLocationModel?>();
      final version = Completer<String>();
      final token = Completer<String?>();
      QsIpLocation.location = () => location.future;
      QsDeviceInfo.version = () => version.future;
      QsAsaAttributionInfo.token = () => token.future;
      bool? oldResult;
      register().then((v) => oldResult = v);
      clock.elapse(Duration.zero);
      register(user: 'b');
      clock.elapse(Duration.zero);
      expect(oldResult, false);
      clock.elapse(const Duration(seconds: 9));
      expect(adapter.calls, 0);
      clock.elapse(const Duration(seconds: 1));
      expect(adapter.calls, 1);
      location.complete(null);
      version.complete('late');
      token.complete('late');
      clock.elapse(Duration.zero);
      expect(adapter.calls, 1);
      expect(QsStorageTool.writes, 1);
    });
  });
  test('custom attribution field and failed preparation fallback', () {
    fakeAsync((clock) {
      QsDeviceInfo.version = () => Future.error(StateError('device failed'));
      register();
      clock.elapse(Duration.zero);
      // Compare encrypted payload against separately prepared expected values.
      final expected = QsAesEncrypt.encrypt(
        secretKey: '0123456789abcdef', iv: '0123456789abcdef',
        content: jsonEncode({'userId':'a','fcmId':'fcm','appVersion':'',
          'deviceType':'ios','deviceModel':'model','os':'os','timezone':'',
          'locale':'en','country':'','state':'','city':'','ip':'','push':true,
          'customToken':'token'}));
      expect(jsonDecode(adapter.requests.single.data as String)['data'], expected);
    });
  });
  test('new calls wait for success commit and reuse global registered state', () {
    fakeAsync((clock) {
      final write = Completer<bool>();
      QsStorageTool.write = () => write.future;
      register();
      clock.elapse(Duration.zero);
      bool? result;
      register(user: 'b').then((v) => result = v);
      clock.elapse(Duration.zero);
      expect(adapter.calls, 1);
      expect(result, null);
      QsStorageTool.registered = true;
      write.complete(true);
      clock.elapse(Duration.zero);
      expect(result, true);
      expect(adapter.calls, 1);
      expect(QsUserRegister._commitFuture, null);
    });
  });
  test('storage write timeout releases commit barrier', () {
    fakeAsync((clock) {
      QsStorageTool.write = () => Completer<bool>().future;
      bool? result;
      register().then((v) => result = v);
      clock.elapse(Duration.zero);
      clock.elapse(const Duration(seconds: 3));
      expect(result, true);
      expect(QsUserRegister._commitFuture, null);
      expect(QsUserRegister._activeTask, null);
    });
  });
  test('storage read timeout and transport exception recover', () {
    fakeAsync((clock) {
      QsStorageTool.read = () => Completer<bool?>().future;
      adapter.respond = (n) => n == 1 ? Future.error(StateError('transport failed')) : Future.value(body(code: 0));
      register();
      clock.elapse(const Duration(seconds: 3));
      expect(adapter.calls, 1);
      QsStorageTool.read = null;
      clock.elapse(const Duration(seconds: 5));
      expect(adapter.calls, 2);
      expect(QsStorageTool.writes, 1);
    });
  });
  test('replacement while reading storage cannot start a stale request', () {
    fakeAsync((clock) {
      final oldRead = Completer<bool?>();
      QsStorageTool.read = () => oldRead.future;
      bool? oldResult;
      register().then((v) => oldResult = v);
      clock.elapse(Duration.zero);
      QsStorageTool.read = null;
      register(user: 'b');
      clock.elapse(Duration.zero);
      oldRead.complete(false);
      clock.elapse(Duration.zero);
      expect(oldResult, false);
      expect(adapter.calls, 1);
      expect(QsStorageTool.writes, 1);
    });
  });
  test('only HTTP 200 and numeric code zero are success', () {
    fakeAsync((clock) {
      adapter.respond = (n) async => switch (n) {
        1 => ResponseBody.fromString('{"code":0}', 201, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]}),
        2 => ResponseBody.fromString('{"code":"0"}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]}),
        3 => ResponseBody.fromString('[]', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]}),
        _ => body(code: 0),
      };
      register();
      clock.elapse(Duration.zero);
      for (var i = 0; i < 3; i++) {
        expect(QsStorageTool.writes, 0);
        clock.elapse(const Duration(seconds: 5));
      }
      expect(adapter.calls, 4);
      expect(QsStorageTool.writes, 1);
      expect(QsUserRegister._activeTask, null);
    });
  });
  test('changed mapping replaces task and latest call wins during commit wait', () {
    fakeAsync((clock) {
      final write = Completer<bool>();
      QsStorageTool.write = () => write.future;
      register();
      clock.elapse(Duration.zero);
      bool? replaced;
      register(user: 'b').then((v) => replaced = v);
      register(user: 'c', tokenField: 'latestToken');
      QsStorageTool.write = null;
      write.complete(false);
      clock.elapse(Duration.zero);
      expect(replaced, false);
      expect(adapter.calls, 2);
      expect(QsStorageTool.writes, 2);
      expect(QsUserRegister._activeTask, null);
    });
  });
  test('real loopback HTTP request preserves body header and success contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    QsUserRegister._dio.httpClientAdapter = IOHttpClientAdapter();
    final received = Completer<void>();
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.headers.value('sct'), 'sct');
      expect(jsonDecode(await utf8.decoder.bind(request).join())['data'], isA<String>());
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"code":0}');
      await request.response.close();
      received.complete();
    });
    try {
      expect(await register(url: 'http://127.0.0.1:${server.port}/register'), true);
      await received.future;
    } finally {
      await server.close(force: true);
      QsUserRegister._dio.httpClientAdapter.close(force: true);
    }
  });
}
