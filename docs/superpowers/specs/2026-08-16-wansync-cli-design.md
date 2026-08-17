# WanSync CLI（wansync）设计

## 概述

把 App 现有的"OneLap → Strava/Xingzhe/Intervals.icu/Outbase"同步机制做成一个跨平台（Linux / macOS / Windows）终端 CLI 程序，用于在服务器或任何终端环境中无人值守运行同步。

**极简原则**（用户明确要求）：CLI 不做任何认证/授权流程——没有 OAuth 浏览器流程、没有手动粘贴 code/cookie、没有"自动获取密钥"。配置全部来自 **App 导出的配置文件 JSON**，直接导入即可使用。

命令面收敛为**单一命令** `wansync sync`。

## 决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 命令面 | 只有 `sync` 一个子命令 | 用户要求极简，"只要 sync"，无 history/watch 附加命令 |
| 配置来源 | `--config` 直接指向 App 导出的 JSON | App 已有导出功能，`AppConfig.fromJson` 自带版本校验，零新增流程 |
| 认证流程 | 完全不实现 | 用户："什么自动获取密钥什么的，我们 CLI 程序不需要" |
| Strava 上传模式 | 仅 API 模式（OAuth token 自动刷新） | web 模式 cookie 会过期，不适合无人值守 CLI；`ensureAccessToken()` 已实现自动刷新 |
| token 刷新回写 | 原地更新 `--config` 指向的 JSON 文件（strava 段三个字段） | 刷新由 API 自动完成，无需人工；回写保证下次运行继续有效 |
| 判重状态落盘 | 默认 `~/.wansync/state.json` | 判重状态必须持久化，否则每次全量重传；与 App 端 state.json 互不冲突 |
| 跨平台分发 | `dart compile exe` 原生二进制 | 同一份代码产出 Linux/macOS/Windows 三个可执行文件 |
| 代码组织 | 提取纯 Dart 包 `packages/sync_core`，App 与 CLI 共用 | standalone `dart pub get` 无法解析 `sdk: flutter`，CLI 不能 `path:` 依赖 Flutter 包 |
| 输出格式 | 人类可读文本（默认）+ `--json` 机器可读 | 便于 cron 日志与脚本消费 |
| **语言选择** | **保持 Dart（`dart compile exe` AOT）** | 目标设备为Linux ARM64 设备（8 核 Kryo 385、4-8GB RAM、几十 GB 存储，资源充裕），Dart AOT 单文件产物实测空程序 5.3MB、完整程序约 10~20MB，零依赖"拷贝即跑"；换 Rust 需重写 3000+ 行同步逻辑（sync_engine 1328 行、onelap_client 885 行、xingzhe_client 435 行、outbase_client 248 行、FIT 解析、加密、坐标转换）且 App(Dart)/CLI(Rust) 永久双维护，体积收益 15MB→1MB 在该设备上无实际意义 |

### 架构约束：目标 CPU

- **目标设备：Linux ARM64 设备（如骁龙 845 手机 + Ubuntu）**——Dart SDK 原生支持 linux-arm64，可直接在手机上装 Dart SDK 编译，或 CI 的 `ubuntu-24.04-arm` runner 交叉产出后拷贝
- 树莓派 **Zero 一代**：ARMv6，**现代 Dart 不支持**（Dart 仅支持 linux-arm ARMv7+ 与 arm64）——仅作参考，与当前目标无关
- Linux x64 / macOS / Windows：原生支持，同一份代码分别编译

## 前置条件（CLI 使用前提）

配置 JSON 内的凭据由 App 侧提前就绪：

| 平台 | 前置条件 | 过期风险 |
|------|---------|---------|
| OneLap | 账号密码（配置内） | 无，每次运行即时登录 |
| Strava | 需在 App 中完成过一次 OAuth（配置内有 refreshToken） | access token 过期由 CLI 自动刷新；refresh token 有效期内无需人工 |
| Xingzhe | 需在 App 中登录过（配置内有 sessionId） | sessionId 过期后需重新在 App 登录并重新导出配置 |
| Intervals.icu | API Key（配置内） | 无 |
| Outbase | sessionId（配置内） | 过期后需在 App 重新登录并重新导出配置 |

## 命令接口

```
wansync sync [--config <file>] [--lookback <N>] [--platform <list>]
             [--json] [--state-dir <dir>] [--verbose]
wansync --help | --version
```

| 参数 | 说明 |
|------|------|
| `--config <file>` | App 导出的配置文件 JSON 路径（必填）。用 `AppConfig.fromJson` 解析并校验版本 |
| `--lookback <N>` | 覆盖配置内 `sync.lookbackDays`，向后回看 N 天 |
| `--platform <list>` | 覆盖 `uploadTo*` 开关，逗号分隔，如 `strava,xingzhe`。仅同步列出的平台 |
| `--json` | 以 JSON 输出 SyncSummary |
| `--state-dir <dir>` | state.json 与临时 FIT 目录位置，默认 `~/.wansync/` |
| `--verbose` | 输出详细日志（进度、每文件结果） |

### 退出码

| 码 | 含义 |
|----|------|
| 0 | 同步完成，无失败（允许存在 deduped） |
| 1 | 同步完成，但存在失败项 |
| 2 | 参数错误 |
| 3 | 配置文件无效（格式/版本/缺字段） |
| 4 | 运行时错误（网络完全不可用等） |

## 配置导入与装配

配置 JSON 结构（与 App 导出完全一致，`version=1`）：

```json
{
  "version": 1,
  "appVersion": "1.0.23",
  "exportedAt": "2026-08-16T10:00:00.000Z",
  "settings": {
    "onelap": { "username": "...", "password": "..." },
    "strava": { "uploadMode": "api", "clientId": "...", "clientSecret": "...",
                "refreshToken": "...", "accessToken": "...", "expiresAt": "...", "webCookies": "..." },
    "xingzhe": { "username": "...", "password": "...", "sessionId": "..." },
    "intervalsIcu": { "athleteId": "...", "apiKey": "..." },
    "outbase": { "sessionId": "..." },
    "sync": { "lookbackDays": 3, "gcjCorrectionEnabled": false,
              "uploadToStrava": true, "uploadToXingzhe": false,
              "uploadToIntervalsIcu": false, "uploadToOutbase": false }
  }
}
```

装配流程（伪代码，核心约 60 行）：

```dart
final config = AppConfig.fromJson(jsonDecode(await File(configPath).readAsString()));
final s = config.settings;
final stateDir = argStateDir ?? '${Platform.environment['HOME']}/.wansync';
final stateStore = FileStateStore(File('$stateDir/state.json'));
final downloadDir = Directory('$stateDir/fit_downloads');

final oneLap = OneLapClient(baseUrl: 'https://www.onelap.cn')
  ..credentials(s['onelap']['username'], s['onelap']['password']);

final strava = s['strava']['uploadMode'] == 'web'
  ? throw UsageError('CLI 不支持 web 模式，请在 App 中使用 API 模式重新导出')
  : StravaClient(
      clientId: ..., clientSecret: ..., refreshToken: ...,
      accessToken: ..., expiresAt: ...,
      tokenPersist: (at, rt, exp) => writeBackConfig(configPath, at, rt, exp));

final xingzhe = XingzheClient(sessionId: s['xingzhe']['sessionId']);
final intervalsIcu = IntervalsIcuClient(athleteId: ..., apiKey: ...);
final outbase = OutbaseClient(sessionId: s['outbase']['sessionId']);

final engine = SyncEngine(
  oneLapClient: oneLap, stravaClient: strava, xingzheClient: xingzhe,
  intervalsIcuClient: intervalsIcu, outbaseClient: outbase,
  stateStore: stateStore, gcjCorrectionEnabled: ...,
  rewriteService: FitCoordinateRewriteService(),
  uploadToStrava: ..., uploadToXingzhe: ..., uploadToIntervalsIcu: ..., uploadToOutbase: ...,
  downloadConcurrency: 3,
);

final summary = await engine.runOnce(lookbackDays: ...);
print(formatSummary(summary));  // 或 summary.toJson()（--json）
exitCode = summary.failed == 0 ? 0 : 1;
```

### 输出示例

```
WanSync sync — 2026-08-16T10:00:00Z
  OneLap 获取: 5 个活动
  判重跳过: 2
  成功上传: 3
  Strava:     成功 3 | 失败 0 | 判重 2
  Xingzhe:    未启用
  Intervals:  未启用
  Outbase:    未启用
```

## 代码改造（三阶段）

### 阶段 1：注入化重构（App 行为零变化，`flutter test` 全绿验证）

仅 5 处 Flutter 阻塞点，全部改为构造参数注入，默认值保持现有行为：

| 文件 | 现状 | 改造 |
|------|------|------|
| `lib/services/state_store.dart:31-34` | `getApplicationDocumentsDirectory()/state.json` | 构造参数 `File? stateFile`，默认取原路径 |
| `lib/services/sync_engine.dart:90` | `getApplicationCacheDirectory()/fit_downloads` | 构造参数 `Directory? downloadDir`，默认取原路径 |
| `lib/services/settings_service.dart` | `SettingsStore` 抽象已存在（readAll/read/write） | 新增 `MapSettingsStore` / `FileSettingsStore` 纯 Dart 实现；`SecureSettingsStore` 不变 |
| `lib/services/strava_client.dart:28` | 硬编码 `_settingsService = SettingsService()` | 构造参数 `tokenPersist` 回调（或 store），默认写 SettingsService |
| `lib/services/xingzhe_client.dart:74` | `create()` 内硬编码 `SettingsService` | 构造参数注入 store（CLI 从配置读 sessionId，不写回） |
| `lib/services/outbase_client.dart:6` | `import 'package:flutter/foundation.dart'`（kDebugMode/debugPrint） | 移除 Flutter import：debugPrint 换普通 print 或注入 logger |
| `lib/services/config_service.dart` | 依赖 package_info_plus 取默认版本号 | 已有 `appVersion` 参数可覆盖；CLI 侧直接传版本号，不依赖该包 |

验证：`dart format` + `flutter analyze` + `flutter test` 全绿；`git diff` 确认 App 行为无变化。

### 阶段 2：提取纯 Dart 包 `packages/sync_core`

- `packages/sync_core/pubspec.yaml`：纯 Dart（无 `flutter` sdk 依赖）；deps：`dio`、`crypto`、`encrypt`、`fit_tool`、`pointycastle`、`http_parser`（与 App 现有版本一致）
- 移入：`lib/models/*`（全部纯 Dart）、`lib/services/` 中纯 Dart 文件（sync_engine、onelap_client、strava_client、strava_upload_client、xingzhe_client、intervals_icu_client、outbase_client、state_store、dedupe_service、concurrency_pool、coordinate_converter、fit_coordinate_rewrite_service、isolate_helpers、settings_service 中纯 Dart 部分、app_config、config_service 纯 Dart 部分）
- App 侧删除被移文件，改为 `path: ../packages/sync_core` 依赖，`lib/` 内 import 改为 `package:sync_core/...`
- UI 专属文件（screens、main.dart、strava_oauth_service、strava_web_client、strava_web_sync_adapter、shared_fit_upload_service 视依赖决定）留在 App 包
- `isolate_helpers.dart` 已用 `dart:isolate` 的 `Isolate.run`（非 flutter compute），可直接进入 sync_core

验证：`flutter test` 全绿 + 新增 `packages/sync_core` 内独立 `dart test`（package:test）。

### 阶段 3：CLI 包 `packages/wansync_cli`

- `packages/wansync_cli/pubspec.yaml`：deps `args`、`sync_core`；dev_deps `test`
- `bin/wansync.dart`：入口，解析参数 → 装配（见上文伪代码）→ 输出
- `lib/`：参数解析、配置读取（含 token 回写）、Summary 格式化（文本/JSON）
- 构建：`dart compile exe bin/wansync.dart -o dist/wansync-linux-x64`（每平台一次）

## 错误处理

| 场景 | 处理 |
|------|------|
| `--config` 文件不存在/不可读 | 退出码 2，stderr 提示 |
| JSON 格式错误 | 退出码 3，"配置文件格式无效" |
| 缺 `version` 字段 | 退出码 3，"配置文件格式无效：缺少版本信息" |
| 不支持的版本号 | 退出码 3，"配置文件版本不受支持" |
| strava.uploadMode == web | 退出码 3，提示改用 API 模式 |
| 单平台失败（Strava 401 等） | 计入 summary.failed，其余平台继续；退出码 1 |
| OneLap 登录失败（风险控制等） | 退出码 4，提示账号/风险控制 |
| 配置回写失败（文件只读） | 仅警告，本次运行仍成功（下次可能需重新刷新） |

## 测试策略

- `packages/sync_core/test/`（package:test）：迁移现有 service 测试 + 新增 `FileStateStore`、`MapSettingsStore` 测试
- `packages/wansync_cli/test/`：参数解析（缺参/非法值/--platform 过滤）、配置读取与 token 回写、Summary 文本/JSON 格式化、退出码
- App 侧 `flutter test`：回归，确认重构零行为变化

## CI 与发布

- `.github/workflows/ci.yml` 新增 job：`dart pub get`（sync_core + cli）→ `dart test` → `dart analyze`；再起一个矩阵 job 在 `ubuntu-latest / macos-latest / windows-latest / ubuntu-24.04-arm` 上 `dart compile exe` 并上传 artifact（arm64 runner 产出树莓派 Zero 2 W 可用的单文件二进制）
- 发布：GitHub Release 附各平台二进制（复用现有 release 流程）
- 文档：README 增加 CLI 一节（中文为主，双语惯例保留）

## 验收标准

1. App 行为零变化：`flutter test` 全绿，无 UI/状态改动
2. `wansync sync --config app-config.json` 在 macOS 本地完成一次真实同步（含 Strava 自动刷新与回写）
3. Linux/macOS/Windows 三平台二进制可编译
4. 连续两次运行：第二次判重跳过已同步活动，不重复上传
