# qs_user_register

用户注册插件，用于在 Android / iOS 应用中上报用户、设备、Firebase App ID、IP 位置、推送状态和 iOS 归因信息。

插件当前只暴露 `QsUserRegister.register` 一个注册入口。`getPlatformVersion` 属于 Flutter 模板示例方法，已从插件 API 中移除。

从 `1.0.1` 开始，调用方不再需要传入 iOS 归因 token。插件会在 iOS 端通过 `qs_asa_attribution_info` 自动获取 ASA attribution token，并在获取成功时随注册参数一起上报。

当前版本为 `1.0.7`。注册时必须传入 `QsUserRegisterApiParameterNameModel`，配置注册数据的字段名；设备型号通过模型的 `deviceModel` 属性指定上报字段名。

## 安装

在项目 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  qs_user_register: ^1.0.7
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
      firebaseAppId: 'firebaseAppId',
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
    firebaseAppId: 'your_firebase_app_id',
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

建议在应用启动后，并且已经拿到 `userId`、`fcmId`、`firebaseAppId` 等必要参数时调用一次。应用重启后如果仍需要确保注册成功，可以再次调用 `register`。

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
  required String firebaseAppId,
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
| `firebaseAppId` | 调用方传入的 Firebase App ID |
| `locale` | 用户语言环境，例如 `zh_CN`、`en_US` |
| `pushState` | 推送开关 |

### Firebase App ID 与升级说明

`firebaseAppId` 为必填参数，升级后需要同时补齐两个位置：

- `QsUserRegister.register(firebaseAppId: ...)`：传入实际 Firebase App ID。
- `QsUserRegisterApiParameterNameModel(firebaseAppId: ...)`：传入后端接收该值的字段名，例如 `firebaseAppId` 或 `firebase_app_id`。

插件不会自动获取 Firebase App ID，也不要求新增 Firebase 依赖。调用方应从业务项目已有的 Firebase 配置或初始化结果中取得该值；它与 `fcmId` 分别作为独立字段传入。

该值会随其他注册数据一起进行 JSON 编码和 AES 加密。更换 Firebase App ID 或其字段映射会替换尚未完成的活动任务；本地已标记注册成功时，仍直接返回 `true`，不会因新增或更换此参数重新上报。

## 返回值

`register` 返回 `Future<bool>`：

- `true`：本次请求注册成功，或本地已经标记为注册成功。
- `false`：当前平台不支持、JSON 编码或加密失败、本次接口请求失败、相同任务已进入重试，或尚未完成的调用被新参数替换。

接口请求失败时会启动后台重试；当前平台不支持、JSON 编码失败或 AES 加密返回空字符串不会启动后台重试。加密异常会被任务捕获并返回 `false`，不启动重试。

## 请求行为

插件直接使用独立 Dio 实例，不再直接依赖 `qs_net_request`。插件会先组装注册参数，再进行 JSON 编码和 AES 加密，最终通过 HTTP POST 以如下 JSON 格式请求接口：

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

接口 HTTP 状态码为 `200`、响应为 JSON 对象且 `code == 0` 时视为注册成功；字符串 `"0"` 不视为成功。注册成功后，插件会尝试在本地保存注册状态；本地状态为已注册时，后续调用 `register` 会直接返回 `true`，不会重复请求接口。保存失败只记录日志，不改变本次成功返回值。

注册状态使用固定存储键 `isRegisterKey`，不按 `userId` 或接口地址区分，也未提供公开的重置接口。因此，更换用户、推送 ID 或其他参数不会自动重新上报。

## 上报字段

`QsUserRegisterApiParameterNameModel` 中的值表示服务端字段名，不是实际业务数据。模型需要单独导入，主入口文件未导出该类型。字段名应非空且互不重复，避免组装 Map 时覆盖数据。

Android 和 iOS 的通用字段均使用模型映射。下面列出模型属性及上述示例对应的请求字段：

| 模型属性 | 示例请求字段 | 说明 |
| --- | --- | --- |
| `userId` | `userId` | 用户 ID |
| `fcmId` | `fcmId` | 推送 ID |
| `firebaseAppId` | `firebaseAppId` | 调用方传入的 Firebase App ID |
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

`attributionToken` 的实际请求字段名由模型同名属性指定；示例使用 `attributionToken`。外层 `data`、请求头 `sct` 和响应判定字段 `code` 也不受模型配置影响。

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

每次请求失败或本轮异常处理结束后，固定等待 **5 秒** 再重试，没有次数上限，不递增、不添加随机抖动。两次请求开始时间之间还包含请求耗时。成功后尝试保存本地状态并停止。

重试复用已加密的数据，不会每次重新获取设备信息、IP 位置或 ASA token。

所有入参及字段映射值相同的调用会复用活动任务：首次结果未完成时共享该结果；已进入后台重试时返回 `false`，不会增加即时请求。不同参数的调用会取消旧请求和重试等待，以最新参数重新注册；尚未完成的旧调用返回 `false`。旧任务迟到的结果不会启动请求或写入成功状态。

成功状态已开始写入时，新调用先等待该次有界写入完成，再按现有全局注册状态处理。取消请求不能撤销服务器已经执行的操作。

## 超时

- 位置获取最多等待 10 秒；应用版本、设备型号、系统版本及 iOS 归因 token 分别最多等待 5 秒，独立信息并行获取。
- 非必要信息异常或超时后沿用空值降级，归因 token 缺失时不传该字段。底层不支持取消的信息获取只停止等待，迟到结果不影响任务。
- 注册状态读取和写入分别最多等待 3 秒；读取失败视为未注册，写入失败不改变服务器已成功的结果。超时不能撤销已经提交到底层存储的写入。
- Dio 的连接、发送、接收超时均为 30 秒；另有单次请求整体 30 秒期限，到期会取消请求并按失败处理。

## 注意事项

- 当前仅支持 Android 和 iOS；未命中本地已注册状态时，其他原生平台会返回 `false`，且不会启动后台重试。插件使用 `dart:io`，不支持 Web。
- iOS 会通过 `qs_asa_attribution_info` 自动获取 ASA 归因 token；获取失败时不会阻断注册，也不会携带 `attributionToken` 字段。
- 插件会通过 IP 获取粗略位置；位置获取失败不会阻断注册，对应字段会使用空字符串。
- 设备信息或应用版本获取失败不会阻断注册，对应字段会使用空字符串。
- 后台重试只在当前应用进程内生效；应用被杀死后任务会停止，应用重启后需要业务方重新调用 `register`。

## 验证

```bash
flutter analyze
flutter test
python3 tool/run_reliability_tests.py
```

以上命令请依次执行，避免多个 Flutter 测试进程同时写入同一构建目录。

回归脚本在 `.dart_tool` 的临时目录组装当前源码及测试替身，验证私有任务生命周期，不向生产 API 添加测试入口。平台判断、信息获取和存储使用测试替身；Dio 保持真实实现，覆盖模拟传输与本地 HTTP 服务，以及 Firebase App ID 自定义字段上报、参数变化替换任务和相同参数复用。该验证不替代 Android/iOS 真机测试。
