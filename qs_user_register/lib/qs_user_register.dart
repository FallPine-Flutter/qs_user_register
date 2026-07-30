import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ip_location/ip_location.dart';
import 'package:ip_location/ip_location_model.dart';
import 'package:qs_aes_encrypt/qs_aes_encrypt.dart';
import 'package:qs_device_info/qs_device_info.dart';
import 'package:qs_log/qs_log.dart';
import 'package:qs_net_request/qs_net_request.dart';
import 'package:qs_storage_tool/qs_storage_tool.dart';

import 'qs_user_register_platform_interface.dart';

class QsUserRegister {
  Future<String?> getPlatformVersion() {
    return QsUserRegisterPlatform.instance.getPlatformVersion();
  }

  // 标记是否已注册
  static const _kIsRegisterKey = "isRegisterKey";

  // 后台重试间隔逐步拉长，最大保持 1 分钟。
  static const _kRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(minutes: 1),
  ];

  static bool _isRetrying = false;
  static String? _retryApiUrl;
  static String? _retryAesSctToken;
  static String? _retryEncryptedParams;

  /// 注册
  static Future<bool> register({
    required String apiUrl, // 接口地址
    required String aesSecretKey, // aes secret key
    required String aesIv, // aes iv
    required String aesSctToken, // aes sct token
    required String userId, // 用户ID
    required String fcmId, // 推送 ID
    required String locale, // 用户语言环境，例如 en_US
    required bool pushState, // 推送开关，true/false 或 1/0
    required String iosAttributionToken, // iOS 归因 token
  }) async {
    // 是否已注册
    if (await _isRegistered()) {
      QsLog.info("已注册");
      return true;
    }

    // 只支持移动端注册，平台判断不依赖上报用的 deviceType 字段。
    if (!Platform.isAndroid && !Platform.isIOS) {
      QsLog.error("当前平台不支持注册");
      return false;
    }

    // 获取位置信息
    final location = await _getLocationByIp();

    Map<String, dynamic> params = {
      "userId": userId,
      "fcmId": fcmId,
      "appVersion": await _getAppVersion(),
      "deviceType": _getDeviceType(),
      "deviceModel": await _getDeviceModel(),
      "deviceOSVersion": await _getDeviceOSVersion(),
      "timezone": location?.timezone ?? "",
      "locale": locale,
      "ipCountry": location?.country ?? "",
      "ipState": location?.regionName ?? "",
      "ipCity": location?.city ?? "",
      "ipAddress": location?.query ?? "",
      "pushState": pushState,
    };

    // iOS 独有归因字段，对外参数名加 ios 前缀避免调用方误解平台范围。
    if (Platform.isIOS) {
      params["attributionToken"] = iosAttributionToken;
    }

    return _register(
      apiUrl: apiUrl,
      aesSecretKey: aesSecretKey,
      aesIv: aesIv,
      aesSctToken: aesSctToken,
      params: params,
    );
  }

  static Future<bool> _register({
    required String apiUrl, // 接口地址
    required String aesSecretKey, // aes secret key
    required String aesIv, // aes iv
    required String aesSctToken, // aes sct token
    required Map<String, dynamic> params, // 注册参数
  }) async {
    final content = _myJsonEncode(params);
    if (content.isEmpty) {
      return false;
    }

    // JSON 或 AES 失败属于本地不可恢复错误，不启动后台重试。
    String encryptedParams = QsAesEncrypt.encrypt(
      secretKey: aesSecretKey,
      iv: aesIv,
      content: content,
    );
    if (encryptedParams.isEmpty) {
      QsLog.error("加密失败");
      return false;
    }

    final isSuccess = await _requestRegister(
      apiUrl: apiUrl,
      aesSctToken: aesSctToken,
      encryptedParams: encryptedParams,
    );
    if (isSuccess) {
      await _markRegistered();
      QsLog.info("注册成功");
      return true;
    }

    _startRetryTask(
      apiUrl: apiUrl,
      aesSctToken: aesSctToken,
      encryptedParams: encryptedParams,
    );
    return false;
  }

  static Future<bool> _requestRegister({
    required String apiUrl,
    required String aesSctToken,
    required String encryptedParams,
  }) async {
    try {
      var response = await QsNetRequest.getInstance().postJson(
        apiUrl,
        parameters: {"data": encryptedParams},
        headers: {"sct": aesSctToken},
        isShowLoading: false,
        onError: (error) {
          QsLog.error("注册接口请求失败: ${error.message}");
        },
      );

      if (response?["code"] == 0) {
        return true;
      }

      QsLog.error("注册接口返回失败: $response");
      return false;
    } catch (e) {
      QsLog.error("注册接口请求异常: $e");
      return false;
    }
  }

  static void _startRetryTask({
    required String apiUrl,
    required String aesSctToken,
    required String encryptedParams,
  }) {
    _retryApiUrl = apiUrl;
    _retryAesSctToken = aesSctToken;
    _retryEncryptedParams = encryptedParams;

    // 已有后台任务时只更新参数，避免多个无限重试循环同时请求。
    if (_isRetrying) {
      QsLog.info("注册后台重试任务已更新");
      return;
    }

    _isRetrying = true;
    unawaited(_runRetryTask());
  }

  static Future<void> _runRetryTask() async {
    var retryIndex = 0;

    // 进程内无限重试；应用重启后由业务方再次调用 register 发起。
    while (true) {
      final delay = _retryDelay(retryIndex);
      await Future.delayed(delay);

      if (await _isRegistered()) {
        _stopRetryTask();
        QsLog.info("已注册，停止后台重试");
        return;
      }

      final apiUrl = _retryApiUrl;
      final aesSctToken = _retryAesSctToken;
      final encryptedParams = _retryEncryptedParams;
      if (apiUrl == null || aesSctToken == null || encryptedParams == null) {
        _stopRetryTask();
        return;
      }

      QsLog.info("注册后台重试第${retryIndex + 1}次");
      final isSuccess = await _requestRegister(
        apiUrl: apiUrl,
        aesSctToken: aesSctToken,
        encryptedParams: encryptedParams,
      );

      if (isSuccess) {
        await _markRegistered();
        _stopRetryTask();
        QsLog.info("注册成功");
        return;
      }

      retryIndex++;
    }
  }

  static Duration _retryDelay(int retryIndex) {
    if (retryIndex < _kRetryDelays.length) {
      return _kRetryDelays[retryIndex];
    }
    return _kRetryDelays.last;
  }

  static void _stopRetryTask() {
    _isRetrying = false;
    _retryApiUrl = null;
    _retryAesSctToken = null;
    _retryEncryptedParams = null;
  }

  static Future<bool> _isRegistered() async {
    try {
      return await QsStorageTool.getBool(key: _kIsRegisterKey) ?? false;
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
      );
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
      return await QsDeviceInfo.getDeviceModel();
    } catch (e) {
      QsLog.error("获取设备型号失败: $e");
      return "";
    }
  }

  static Future<String> _getDeviceOSVersion() async {
    try {
      return await QsDeviceInfo.getDeviceOSVersion();
    } catch (e) {
      QsLog.error("获取设备系统版本失败: $e");
      return "";
    }
  }

  static Future<String> _getAppVersion() async {
    try {
      return await QsDeviceInfo.getAppVersion() ?? "";
    } catch (e) {
      QsLog.error("获取应用版本失败: $e");
      return "";
    }
  }

  /// 根据 IP 获取省市区信息
  static Future<IpLocationModel?> _getLocationByIp() async {
    try {
      IpLocationModel? location = await IpLocation.getIpLocation();
      return location;
    } catch (e) {
      QsLog.error("获取位置信息失败: $e");
      return null;
    }
  }

  /// 自定义 JSON 编码
  static String _myJsonEncode(Object? params) {
    try {
      return jsonEncode(params);
    } catch (e) {
      QsLog.error("jsonEncode error: $e");
      return "";
    }
  }
}
