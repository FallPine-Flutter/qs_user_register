# qs_user_register

用户注册插件，用于在 Android / iOS 应用中上报用户、设备、IP 位置、推送状态和 iOS 归因信息。

插件当前只暴露 `QsUserRegister.register` 一个注册入口。`getPlatformVersion` 属于 Flutter 模板示例方法，已从插件 API 中移除。

从 `1.0.1` 开始，调用方不再需要传入 iOS 归因 token。插件会在 iOS 端通过 `qs_asa_attribution_info` 自动获取 ASA attribution token，并在获取成功时随注册参数一起上报。

## 安装

在项目 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  qs_user_register: ^1.0.1
```

然后执行：

```bash
flutter pub get
```

## 使用

```dart
import 'package:qs_user_register/qs_user_register.dart';

Future<void> registerUser() async {
  final isSuccess = await QsUserRegister.register(
    apiUrl: 'https://example.com/api/register',
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
- `false`：当前平台不支持、JSON 编码失败、AES 加密失败，或本次接口请求失败。

接口请求失败时会启动后台重试；当前平台不支持、JSON 编码失败或 AES 加密失败不会启动后台重试。

## 请求行为

插件会先组装注册参数，再进行 JSON 编码和 AES 加密，最终以如下格式请求接口：

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

接口返回 `code == 0` 时视为注册成功。注册成功后，插件会在本地保存注册状态，后续再次调用 `register` 会直接返回 `true`，不会重复请求接口。

## 上报字段

Android 和 iOS 都会上报：

| 字段 | 说明 |
| --- | --- |
| `userId` | 用户 ID |
| `fcmId` | 推送 ID |
| `appVersion` | 应用版本 |
| `deviceType` | 设备类型 |
| `deviceModel` | 设备型号 |
| `deviceOSVersion` | 设备系统版本 |
| `timezone` | IP 定位返回的时区 |
| `locale` | 调用方传入的用户语言环境 |
| `ipCountry` | IP 定位返回的国家或地区 |
| `ipState` | IP 定位返回的省/州 |
| `ipCity` | IP 定位返回的城市 |
| `ipAddress` | IP 地址 |
| `pushState` | 推送开关 |

iOS 会额外上报：

| 字段 | 说明 |
| --- | --- |
| `attributionToken` | iOS 归因 token，由插件内部通过 `qs_asa_attribution_info` 获取；获取失败时不传该字段 |

## ASA 归因

iOS 端会在注册参数组装阶段调用 `QsAsaAttributionInfo.getAttributionToken()` 获取 Apple Search Ads attribution token。

获取成功时，请求参数会增加：

```json
{
  "attributionToken": "apple_search_ads_attribution_token"
}
```

获取失败、系统版本不支持或 token 为空时，插件会继续执行注册流程，但不会携带 `attributionToken` 字段。

`qs_asa_attribution_info` 的 iOS token 获取依赖 Apple `AdServices`，要求 iOS 14.3 或更高版本。低版本 iOS、Android 或其他平台不会阻塞注册主流程。

## 后台重试

如果首次接口请求失败，`register` 会返回 `false`，并在当前应用进程内启动后台重试。

重试间隔会逐步拉长：

```text
5s -> 10s -> 20s -> 40s -> 1min
```

之后固定每 `1min` 重试一次。任意一次重试成功后，会保存本地注册状态并停止后台重试。

重复调用 `register` 时，如果后台重试任务已经存在，插件会更新为最新参数，但不会创建多个重试循环。

## 注意事项

- 当前仅支持 Android 和 iOS；其他平台会返回 `false`，且不会启动后台重试。
- iOS 会通过 `qs_asa_attribution_info` 自动获取 ASA 归因 token；获取失败时不会阻断注册，也不会携带 `attributionToken` 字段。
- 插件会通过 IP 获取粗略位置；位置获取失败不会阻断注册，对应字段会使用空字符串。
- 设备信息或应用版本获取失败不会阻断注册，对应字段会使用空字符串。
- 后台重试只在当前应用进程内生效；应用被杀死后任务会停止，应用重启后需要业务方重新调用 `register`。
