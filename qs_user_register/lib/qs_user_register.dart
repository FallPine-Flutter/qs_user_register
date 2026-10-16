import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:qs_ip_location/qs_ip_location.dart';
import 'package:qs_aes_encrypt/qs_aes_encrypt.dart';
import 'package:qs_asa_attribution_info/qs_asa_attribution_info.dart';
import 'package:qs_device_info/qs_device_info.dart';
import 'package:qs_log/qs_log.dart';
import 'package:dio/dio.dart';
import 'package:qs_storage_tool/qs_storage_tool.dart';
import 'package:qs_user_register/qs_user_register_api_parameter_name_model.dart';

part 'src/register_task.dart';

class QsUserRegister {
  /// Custom Funcs
  /// 注册
  static Future<bool> register({
    required String apiUrl, // 接口地址
    required QsUserRegisterApiParameterNameModel apiParameterNameModel,
    required String aesSecretKey, // aes secret key
    required String aesIv, // aes iv
    required String aesSctToken, // aes sct token
    required String userId, // 用户ID
    required String fcmId, // 推送 ID
    required String firebaseAppId, // firebase AppId
    required String locale, // 用户语言环境，例如 en_US
    required bool pushState, // 推送开关，true/false 或 1/0
  }) {
    final input = <String, Object>{
      'apiUrl': apiUrl,
      'aesSecretKey': aesSecretKey,
      'aesIv': aesIv,
      'aesSctToken': aesSctToken,
      'userId': userId,
      'fcmId': fcmId,
      'firebaseAppId': firebaseAppId,
      'locale': locale,
      'pushState': pushState,
      'field.userId': apiParameterNameModel.userId,
      'field.fcmId': apiParameterNameModel.fcmId,
      'field.firebaseAppId': apiParameterNameModel.firebaseAppId,
      'field.appVersion': apiParameterNameModel.appVersion,
      'field.deviceType': apiParameterNameModel.deviceType,
      'field.deviceModel': apiParameterNameModel.deviceModel,
      'field.deviceOSVersion': apiParameterNameModel.deviceOSVersion,
      'field.timezone': apiParameterNameModel.timezone,
      'field.locale': apiParameterNameModel.locale,
      'field.ipCountry': apiParameterNameModel.ipCountry,
      'field.ipState': apiParameterNameModel.ipState,
      'field.ipCity': apiParameterNameModel.ipCity,
      'field.ipAddress': apiParameterNameModel.ipAddress,
      'field.pushState': apiParameterNameModel.pushState,
      'field.attributionToken': apiParameterNameModel.attributionToken,
    };
    return _submit(input: input);
  }

  static Future<bool> _submit({required Map<String, Object> input}) {
    final current = _activeTask;
    if (current != null && current.matches(input: input)) {
      return current.firstResult.future;
    }
    // 成功提交已开始时先完成有界写入；新调用按到达顺序重新竞争。
    final commit = _commitFuture;
    if (commit != null) {
      return commit.then((_) => _submit(input: input));
    }
    current?.cancel();
    final task = _RegisterTask(input: input);
    _activeTask = task;
    unawaited(_runTask(task: task));
    return task.firstResult.future;
  }

  static bool _isCurrent({required _RegisterTask task}) =>
      identical(_activeTask, task) && !task.cancelled;

  static Future<void> _runTask({required _RegisterTask task}) async {
    try {
      final registered = await _isRegistered();
      if (!_isCurrent(task: task)) return;
      if (registered) {
        task.complete(value: true);
        return;
      }
      // 只支持移动端注册，平台判断不依赖上报用的 deviceType 字段。
      if (!Platform.isAndroid && !Platform.isIOS) {
        QsLog.error('当前平台不支持注册');
        return;
      }
      final params = await _prepareParams(task: task);
      if (!_isCurrent(task: task)) return;
      final content = _myJsonEncode(params: params);
      if (content.isEmpty) return;
      // JSON 或 AES 失败属于本地不可恢复错误，不启动后台重试。
      final encrypted = QsAesEncrypt.encrypt(
        secretKey: task.input['aesSecretKey']! as String,
        iv: task.input['aesIv']! as String,
        content: content,
      );
      if (encrypted.isEmpty) {
        QsLog.error('加密失败');
        return;
      }
      await _runRequests(task: task, encryptedParams: encrypted);
    } catch (e, stack) {
      QsLog.error('注册任务异常: $e\n$stack');
    } finally {
      task.complete(value: false);
      task.cancel();
      if (identical(_activeTask, task)) _activeTask = null;
    }
  }

  static Future<Map<String, dynamic>> _prepareParams({
    required _RegisterTask task,
  }) async {
    // 独立信息并行获取；超时的底层调用即使迟到，也只返回局部结果。
    final values = await Future.wait<Object?>([
      _getLocationByIp(),
      _getAppVersion(),
      _getDeviceModel(),
      _getDeviceOSVersion(),
      Platform.isIOS ? _getAttributionToken() : Future<String?>.value(),
    ]);
    final location = values[0] as QsIpLocationModel?;
    final input = task.input;
    final params = <String, dynamic>{
      input['field.userId']! as String: input['userId'],
      input['field.fcmId']! as String: input['fcmId'],
      input['field.firebaseAppId']! as String: input['firebaseAppId'],
      input['field.appVersion']! as String: values[1],
      input['field.deviceType']! as String: _getDeviceType(),
      input['field.deviceModel']! as String: values[2],
      input['field.deviceOSVersion']! as String: values[3],
      input['field.timezone']! as String: location?.timezone ?? '',
      input['field.locale']! as String: input['locale'],
      input['field.ipCountry']! as String: location?.countryName ?? '',
      input['field.ipState']! as String: location?.regionName ?? '',
      input['field.ipCity']! as String: location?.cityName ?? '',
      input['field.ipAddress']! as String: location?.ip ?? '',
      input['field.pushState']! as String: input['pushState'],
    };
    final token = values[4] as String?;
    if (token != null && token.isNotEmpty) {
      params[input['field.attributionToken']! as String] = token;
    }
    return params;
  }

  static Future<void> _runRequests({
    required _RegisterTask task,
    required String encryptedParams,
  }) async {
    // 进程内无限重试；应用重启后由业务方再次调用 register 发起。
    while (_isCurrent(task: task)) {
      try {
        final success = await _requestRegister(
          task: task,
          encryptedParams: encryptedParams,
        );
        if (!_isCurrent(task: task)) return;
        if (success) {
          // 检查身份到设置提交屏障之间没有 await，禁止旧任务越过替换写入。
          final commit = _markRegistered();
          _commitFuture = commit;
          try {
            await commit;
            task.complete(value: true);
          } finally {
            if (identical(_commitFuture, commit)) _commitFuture = null;
          }
          return;
        }
      } catch (e, stack) {
        QsLog.error('注册重试异常: $e\n$stack');
      }
      if (!_isCurrent(task: task)) return;
      task.complete(value: false);
      await task.waitForRetry();
      if (!_isCurrent(task: task)) return;
      try {
        final registered = await _isRegistered();
        if (!_isCurrent(task: task)) return;
        if (registered) return;
      } catch (e) {
        QsLog.error('重试状态检查异常: $e');
      }
    }
  }

  static Future<bool> _requestRegister({
    required _RegisterTask task,
    required String encryptedParams,
  }) async {
    if (!_isCurrent(task: task)) return false;
    final token = CancelToken();
    task.requestToken = token;
    try {
      final response = await _dio
          .post<dynamic>(
            task.input['apiUrl']! as String,
            data: jsonEncode({'data': encryptedParams}),
            options: Options(
              headers: {'sct': task.input['aesSctToken']},
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
            ),
            cancelToken: token,
          )
          .timeout(
            _requestTimeout,
            onTimeout: () {
              token.cancel('注册请求整体超时');
              throw TimeoutException('注册请求整体超时', _requestTimeout);
            },
          );
      if (!_isCurrent(task: task)) return false;
      return response.statusCode == 200 &&
          response.data is Map &&
          response.data['code'] == 0;
    } catch (e) {
      if (_isCurrent(task: task)) QsLog.error('注册接口请求失败: $e');
      return false;
    } finally {
      if (identical(task.requestToken, token)) task.requestToken = null;
    }
  }

  static Future<bool> _isRegistered() async {
    try {
      return await QsStorageTool.getBool(
            key: _kIsRegisterKey,
          ).timeout(_storageTimeout) ??
          false;
    } catch (e) {
      QsLog.error("读取注册状态失败: $e");
      return false;
    }
  }

  static Future<void> _markRegistered() async {
    try {
      final isSaved = await QsStorageTool.setBool(
        key: _kIsRegisterKey,
        value: true,
      ).timeout(_storageTimeout);
      if (!isSaved) {
        QsLog.error("保存注册状态失败");
      }
    } catch (e) {
      QsLog.error("保存注册状态异常: $e");
    }
  }

  static String _getDeviceType() {
    try {
      return QsDeviceInfo.getDeviceType();
    } catch (e) {
      QsLog.error("获取设备类型失败: $e");
      return "";
    }
  }

  static Future<String> _getDeviceModel() async {
    try {
      return await QsDeviceInfo.getDeviceModel().timeout(_infoTimeout);
    } catch (e) {
      QsLog.error("获取设备型号失败: $e");
      return "";
    }
  }

  static Future<String> _getDeviceOSVersion() async {
    try {
      return await QsDeviceInfo.getDeviceOSVersion().timeout(_infoTimeout);
    } catch (e) {
      QsLog.error("获取设备系统版本失败: $e");
      return "";
    }
  }

  static Future<String> _getAppVersion() async {
    try {
      return await QsDeviceInfo.getAppVersion().timeout(_infoTimeout) ?? "";
    } catch (e) {
      QsLog.error("获取应用版本失败: $e");
      return "";
    }
  }

  static Future<String?> _getAttributionToken() async {
    try {
      return await QsAsaAttributionInfo.getAttributionToken().timeout(
        _infoTimeout,
      );
    } catch (e) {
      QsLog.error("获取ASA归因token失败: $e");
      return null;
    }
  }

  /// 根据 IP 获取省市区信息
  static Future<QsIpLocationModel?> _getLocationByIp() async {
    try {
      QsIpLocationModel? location = await QsIpLocation.getIpLocation().timeout(
        _locationTimeout,
      );
      return location;
    } catch (e) {
      QsLog.error("获取位置信息失败: $e");
      return null;
    }
  }

  /// 自定义 JSON 编码
  static String _myJsonEncode({required Object? params}) {
    try {
      return jsonEncode(params);
    } catch (e) {
      QsLog.error("jsonEncode error: $e");
      return "";
    }
  }

  /// Properties
  // 标记是否已注册
  static const _kIsRegisterKey = 'isRegisterKey';
  static const _storageTimeout = Duration(seconds: 3);
  static const _infoTimeout = Duration(seconds: 5);
  static const _locationTimeout = Duration(seconds: 10);
  static const _requestTimeout = Duration(seconds: 30);
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: _requestTimeout,
      sendTimeout: _requestTimeout,
      receiveTimeout: _requestTimeout,
    ),
  );
  static _RegisterTask? _activeTask;
  static Future<void>? _commitFuture;
}
