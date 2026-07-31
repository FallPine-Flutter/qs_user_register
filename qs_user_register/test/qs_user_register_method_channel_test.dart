import 'package:flutter_test/flutter_test.dart';
import 'package:qs_user_register/qs_user_register_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelQsUserRegister platform = MethodChannelQsUserRegister();

  test('method channel is available', () {
    expect(platform.methodChannel.name, 'qs_user_register');
  });
}
