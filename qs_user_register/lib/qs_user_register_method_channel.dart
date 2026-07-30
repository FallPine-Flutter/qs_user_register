import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'qs_user_register_platform_interface.dart';

/// An implementation of [QsUserRegisterPlatform] that uses method channels.
class MethodChannelQsUserRegister extends QsUserRegisterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('qs_user_register');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
