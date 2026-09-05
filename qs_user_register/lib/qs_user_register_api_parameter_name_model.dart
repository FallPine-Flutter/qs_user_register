class QsUserRegisterApiParameterNameModel {
  QsUserRegisterApiParameterNameModel({
    required this.userId,
    required this.fcmId,
    required this.appVersion,
    required this.deviceType,
    required this.deviceModel,
    required this.deviceOSVersion,
    required this.timezone,
    required this.locale,
    required this.ipCountry,
    required this.ipState,
    required this.ipCity,
    required this.ipAddress,
    required this.pushState,
    required this.attributionToken,
  });

  // 用户ID
  final String userId;
  // 推送 ID
  final String fcmId;
  // 应用版本
  final String appVersion;
  // 设备类型
  final String deviceType;
  // 设备型号
  final String deviceModel;
  // 设备操作系统版本
  final String deviceOSVersion;
  // 时区
  final String timezone;
  // 用户语言环境
  final String locale;
  // IP 国家
  final String ipCountry;
  // IP 省份
  final String ipState;
  // IP 城市
  final String ipCity;
  // IP 地址
  final String ipAddress;
  // 推送开关
  final String pushState;
  // 归因令牌
  final String attributionToken;
}
