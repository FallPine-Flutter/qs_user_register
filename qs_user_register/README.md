# qs_user_register

用户注册插件，用于在 Android / iOS 应用中上报用户、设备、IP 位置、推送状态和 iOS 归因信息。

插件当前只暴露 `QsUserRegister.register` 一个注册入口。`getPlatformVersion` 属于 Flutter 模板示例方法，已从插件 API 中移除。

从 `1.0.1` 开始，调用方不再需要传入 iOS 归因 token。插件会在 iOS 端通过 `qs_asa_attribution_info` 自动获取 ASA attribution token，并在获取成功时随注册参数一起上报。

当前版本为 `1.0.5`。注册时必须传入 `QsUserRegisterApiParameterNameModel`，配置注册数据的字段名；设备型号通过模型的 `deviceModel` 属性指定上报字段名。

## 安装

在项目 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  qs_user_register: ^1.0.5
```

环境要求与当前 `pubspec.yaml` 一致：Dart `^3.11.5`、Flutter `>=3.3.0`，并需使用满足该 Dart 约束的 Flutter SDK。支持 Android 和 iOS。

然后执行：

```bash
flutter pub get
```

## 使用

```dart
import 'package:qs_user_register/qs_user_register.dart';
import 'package:qs_user_register/qs_user_register_api_parameter_name_model.dart';

Future<void> registerUser() async {
  final isSuccess = await QsUserRegister.register(
    apiUrl: 'https://example.com/api/register',
    apiParameterNameModel: QsUserRegisterApiParameterNameModel(
      userId: 'userId',
      fcmId: 'fcmId',
      appVersion: 'appVersion',
      deviceType: 'deviceType',
      deviceModel: 'devicePlatform',
      deviceOSVersion: 'deviceOSVersion',
      timezone: 'timezone',
      locale: 'locale',
      ipCountry: 'ipCountry',
      ipState: 'ipState',
      ipCity: 'ipCity',
      ipAddress: 'ipAddress',
      pushState: 'pushState',
      attributionToken: 'attributionToken',
    ),
    aesSecretKey: 'your_aes_secret_key',
    aesIv: 'your_aes_iv',
    aesSctToken: 'your_sct_token',
    userId: 'user_id',
    fcmId: 'fcm_push_id',
    locale: 'zh_CN',
    pushState: true,
  );

  if (isSuccess) {
    // 已注册成功，或本地已经标记为注册成功。
  } else {
    // 本次注册未成功。接口请求失败时，插件会在当前进程内启动后台重试。
  }
}
```

建议在应用启动后，并且已经拿到 `userId`、`fcmId` 等必要参数时调用一次。应用重启后如果仍需要确保注册成功，可以再次调用 `register`。

## API

```dart
static Future<bool> register({
  required String apiUrl,
  required QsUserRegisterApiParameterNameModel apiParameterNameModel,
  required String aesSecretKey,
  required String aesIv,
  required String aesSctToken,
  required String userId,
  required String fcmId,
  required String locale,
  required bool pushState,
})
```

| 参数 | 说明 |
| --- | --- |
| `apiUrl` | 注册接口地址 |
| `apiParameterNameModel` | 注册数据字段名映射，所有构造参数均为必填 `String` |
| `aesSecretKey` | AES 加密 secret key |
| `aesIv` | AES 加密 IV |
| `aesSctToken` | 请求头 `sct` 的值 |
| `userId` | 用户 ID |
| `fcmId` | 推送 ID |
| `locale` | 用户语言环境，例如 `zh_CN`、`en_US` |
| `pushState` | 推送开关 |

## 返回值

`register` 返回 `Future<bool>`：

- `true`：本次请求注册成功，或本地已经标记为注册成功。
- `false`：当前平台不支持、JSON 编码失败、AES 加密返回空字符串，或本次接口请求失败。

接口请求失败时会启动后台重试；当前平台不支持、JSON 编码失败或 AES 加密返回空字符串不会启动后台重试。当前实现未捕获加密调用本身抛出的异常，调用方可按需使用 `try/catch` 处理。

## 请求行为

插件会先组装注册参数，再进行 JSON 编码和 AES 加密，最终通过 HTTP POST 以如下 JSON 格式请求接口：

```json
{
  "data": "encrypted_register_params"
}
```

请求头会携带：

```json
{
  "sct": "aesSctToken"
}
```

接口返回 `code == 0` 时视为注册成功。注册成功后，插件会尝试在本地保存注册状态；本地状态为已注册时，后续调用 `register` 会直接返回 `true`，不会重复请求接口。保存失败只记录日志，不改变本次成功返回值。

注册状态使用固定存储键 `isRegisterKey`，不按 `userId` 或接口地址区分，也未提供公开的重置接口。因此，更换用户、推送 ID 或其他参数不会自动重新上报。

## 上报字段

`QsUserRegisterApiParameterNameModel` 中的值表示服务端字段名，不是实际业务数据。模型需要单独导入，主入口文件未导出该类型。字段名应非空且互不重复，避免组装 Map 时覆盖数据。

Android 和 iOS 的通用字段均使用模型映射。下面列出模型属性及上述示例对应的请求字段：

| 模型属性 | 示例请求字段 | 说明 |
| --- | --- | --- |
| `userId` | `userId` | 用户 ID |
| `fcmId` | `fcmId` | 推送 ID |
| `appVersion` | `appVersion` | 应用版本 |
| `deviceType` | `deviceType` | 设备类型 |
| `deviceModel` | `devicePlatform` | 设备型号 |
| `deviceOSVersion` | `deviceOSVersion` | 设备系统版本 |
| `timezone` | `timezone` | IP 定位返回的时区 |
| `locale` | `locale` | 调用方传入的用户语言环境 |
| `ipCountry` | `ipCountry` | IP 定位返回的国家或地区 |
| `ipState` | `ipState` | IP 定位返回的省/州 |
| `ipCity` | `ipCity` | IP 定位返回的城市 |
| `ipAddress` | `ipAddress` | IP 地址 |
| `pushState` | `pushState` | 调用方传入的布尔值 |

iOS 会额外上报：

| 字段 | 说明 |
| --- | --- |
| `attributionToken` | iOS 归因 token，由插件内部通过 `qs_asa_attribution_info` 获取；获取失败时不传该字段 |

当前实现中，`attributionToken` 是固定请求字段，未读取模型的同名属性。该属性仍为必填项，建议按示例传入 `'attributionToken'`；设置其他名称不会改变实际请求字段。外层 `data`、请求头 `sct` 和响应判定字段 `code` 也不受模型配置影响。

## ASA 归因

iOS 端会在注册参数组装阶段调用 `QsAsaAttributionInfo.getAttributionToken()` 获取 Apple Search Ads attribution token。

获取成功时，请求参数会增加：

```json
{
  "attributionToken": "apple_search_ads_attribution_token"
}
```

获取失败、系统版本不支持或 token 为空时，插件会继续执行注册流程，但不会携带 `attributionToken` 字段。

token 获取能力由 `qs_asa_attribution_info` 提供，具体系统版本要求以该依赖为准。Android 注册时不会调用 token 获取方法。

## 后台重试

如果首次接口请求失败，`register` 会返回 `false`，并在当前应用进程内启动后台重试。

重试间隔会逐步拉长：

```text
5s -> 10s -> 20s -> 40s -> 1min
```

之后固定每 `1min` 重试一次。任意一次重试成功后，会保存本地注册状态并停止后台重试。

重试复用已加密的数据，不会每次重新获取设备信息、IP 位置或 ASA token。

重复调用 `register` 仍可能发起新的即时请求；该请求失败并进入重试逻辑时，会更新现有重试任务的接口地址、请求头 token 和加密数据，不会另建重试循环。插件未对多个并发 `register` 调用做请求去重，建议调用方避免并发调用。

## 注意事项

- 当前仅支持 Android 和 iOS；未命中本地已注册状态时，其他原生平台会返回 `false`，且不会启动后台重试。插件使用 `dart:io`，不支持 Web。
- iOS 会通过 `qs_asa_attribution_info` 自动获取 ASA 归因 token；获取失败时不会阻断注册，也不会携带 `attributionToken` 字段。
- 插件会通过 IP 获取粗略位置；位置获取失败不会阻断注册，对应字段会使用空字符串。
- 设备信息或应用版本获取失败不会阻断注册，对应字段会使用空字符串。
- 后台重试只在当前应用进程内生效；应用被杀死后任务会停止，应用重启后需要业务方重新调用 `register`。
