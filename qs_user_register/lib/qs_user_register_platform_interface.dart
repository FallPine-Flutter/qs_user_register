import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'qs_user_register_method_channel.dart';

abstract class QsUserRegisterPlatform extends PlatformInterface {
  /// Constructs a QsUserRegisterPlatform.
  QsUserRegisterPlatform() : super(token: _token);

  static final Object _token = Object();

  static QsUserRegisterPlatform _instance = MethodChannelQsUserRegister();

  /// The default instance of [QsUserRegisterPlatform] to use.
  ///
  /// Defaults to [MethodChannelQsUserRegister].
  static QsUserRegisterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [QsUserRegisterPlatform] when
  /// they register themselves.
  static set instance(QsUserRegisterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
