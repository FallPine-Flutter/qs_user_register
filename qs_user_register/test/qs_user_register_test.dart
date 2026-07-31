import 'package:flutter_test/flutter_test.dart';
import 'package:qs_user_register/qs_user_register_platform_interface.dart';
import 'package:qs_user_register/qs_user_register_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockQsUserRegisterPlatform
    with MockPlatformInterfaceMixin
    implements QsUserRegisterPlatform {}

void main() {
  final QsUserRegisterPlatform initialPlatform =
      QsUserRegisterPlatform.instance;

  test('$MethodChannelQsUserRegister is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelQsUserRegister>());
  });
}
