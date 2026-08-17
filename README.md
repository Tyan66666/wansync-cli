# WanSync CLI

把 [顽爪爪 App（WanSync）](https://github.com/Anomaly-Lap/Onelap-Strava-GoGoGo) 的同步机制做成跨平台终端 CLI：导入 App 导出的配置 JSON，即可在 Linux 服务器 / 终端 / 树莓派等 ARM 设备上无人值守同步 OneLap 活动到 Strava / 行者 / Intervals.icu / Outbase。

**零认证流程**：所有凭据来自顽爪爪 App 导出的配置文件，CLI 不做任何 OAuth / cookie 获取。

## 快速开始

```bash
# 编译单文件二进制（Linux / macOS / Windows / ARM64 各平台各自编译）
dart compile exe packages/wansync_cli/bin/wansync.dart -o wansync

# 导入顽爪爪 App 导出的配置 JSON 并同步
./wansync sync --config app-config.json

# 只同步部分平台 / 覆盖回看天数 / JSON 输出
./wansync sync -c app-config.json --platform strava,xingzhe --lookback 7
./wansync sync -c app-config.json --json

# 坐标转换覆盖：强制开启 / 强制关闭（默认用配置 sync.gcjCorrectionEnabled）
./wansync sync -c app-config.json --gcj-correction
./wansync sync -c app-config.json --no-gcj-correction
```

退出码与错误处理的完整说明见下文「退出码与错误处理」章节。

## 获取二进制（按你的设备选一种）

**方式 A：GitHub Actions 下载（推荐，无需本地装 Dart）**

把仓库推到 GitHub 后，CI 会自动编译 4 个平台产物并作为 artifact 上传：

| artifact 名 | 适用设备 |
|---|---|
| `wansync-linux-x64` | 普通 Linux 服务器 / x64 电脑 |
| `wansync-linux-arm64` | Linux ARM64 设备（树莓派、ARM 盒子等） |
| `wansync-macos-arm64` | Mac（Apple Silicon） |
| `wansync-windows-x64` | Windows |

下载后解压得到单个可执行文件，直接拷贝到设备上。

**方式 B：在目标设备上自己编译**

```bash
# 在 Linux 服务器 / ARM 设备上（需先装 Dart SDK）
curl -fsSL https://dart.dev/install.sh | bash   # 或 apt install dart
git clone https://github.com/你的账号/wansync-cli.git
cd wansync-cli/packages/wansync_cli
dart pub get
dart compile exe bin/wansync.dart -o ~/wansync
```

**方式 C：本机编译后拷贝（同架构才行）**

```bash
cd wansync-cli/packages/wansync_cli
dart compile exe bin/wansync.dart -o wansync
```

> 注意：编译出的二进制只能在**相同操作系统 + 相同 CPU 架构**上运行。
> 例如 macOS 上编的（Mach-O）不能拷到 Linux 设备上；x64 编的不能拷到 ARM 设备上。
> ARM 设备（树莓派等）请用方式 A 的 `wansync-linux-arm64`，或在设备上直接编译。

## 在 Linux 上运行（含定时同步）

```bash
# 1. 把二进制和配置放到设备上（scp / U 盘均可）
#    配置 = 顽爪爪 App「设置 → 导出配置」生成的 JSON 文件
mkdir -p ~/wansync ~/.wansync
cp wansync ~/wansync/
cp app-config.json ~/wansync/

# 2. 手动跑一次
~/wansync/wansync sync -c ~/wansync/app-config.json

# 3. 定时自动同步（cron，每 30 分钟一次）
crontab -e
# 添加一行：
*/30 * * * * ~/wansync/wansync sync -c ~/wansync/app-config.json --lookback 1 >> ~/wansync/sync.log 2>&1
```

说明：
- 第一次运行会把 Strava access token 刷新并**回写**到 `app-config.json`（若过期）
- 判重状态存在 `~/.wansync/state.json`，第二次起跳过已同步的活动，不会重复上传
- 查看最近结果：`tail ~/wansync/sync.log`

## 配置文件

`--config` 指向 **[顽爪爪 App](https://github.com/Anomaly-Lap/Onelap-Strava-GoGoGo)「设置 → 导出配置」生成的 JSON**，也可手工编写。仓库根目录附有 `config.json.example`（带完整注释的模板），**复制后填入真实值即可直接使用——配置支持 JSONC 注释（`//` 与 `/* */`），无需删除注释**。结构如下：

```json
{
  "version": 1,
  "appVersion": "1.0.23",
  "exportedAt": "2026-08-16T00:00:00.000Z",
  "settings": {
    "onelap": { "username": "...", "password": "..." },
    "strava": {
      "uploadMode": "api",
      "clientId": "...",
      "clientSecret": "...",
      "refreshToken": "...",
      "accessToken": "...",
      "expiresAt": "..."
    },
    "xingzhe": { "sessionId": "..." },
    "intervalsIcu": { "athleteId": "...", "apiKey": "..." },
    "outbase": { "sessionId": "..." },
    "sync": {
      "lookbackDays": 3,
      "gcjCorrectionEnabled": false,
      "uploadToStrava": true,
      "uploadToXingzhe": false,
      "uploadToIntervalsIcu": false,
      "uploadToOutbase": false
    }
  }
}
```

要点：

| 项目 | 说明 |
|------|------|
| `onelap` | **必填**（数据源）。其余平台按 `sync.uploadTo*` 开关决定是否启用 |
| `strava.uploadMode` | CLI **仅支持 `"api"`**；`web` 模式会直接报配置错误 |
| Strava token | access token 过期时 CLI 自动用 refresh token 刷新，并把新 token **原地回写**到配置文件 |
| `xingzhe` / `outbase` | 需先在顽爪爪 App 中登录（获得 sessionId）再导出；sessionId 过期后需在顽爪爪 App 重新登录导出 |
| `--platform` | 可临时覆盖 `uploadTo*` 开关，不修改配置文件 |
| `--gcj-correction` / `--no-gcj-correction` | 临时覆盖 `sync.gcjCorrectionEnabled`（GCJ-02 → WGS-84 坐标转换），不修改配置文件 |

## 退出码与错误处理

**设计原则：stdout 只输出结果，所有错误信息走 stderr** —— 管道 / 重定向不会被错误信息污染。

| 退出码 | 含义 | 触发场景 |
|---|---|---|
| `0` | 成功 | 同步完成，无失败 |
| `1` | 同步中有失败 | 部分活动上传失败（其余平台照常同步） |
| `2` | 参数错误 | 缺 `--config`、`--lookback` 非整数、`--platform` 未知平台 |
| `3` | 配置无效 | 文件不存在、非法 JSON、版本不受支持、Strava web 模式、缺 OneLap 账号 |
| `4` | 运行时错误 | 网络失败、OneLap 登录失败、未捕获异常 |

stderr 示例：

```
配置无效: 配置文件不存在: /nonexistent.json
配置无效: 配置文件格式无效：不是合法 JSON（支持 // 与 /* */ 注释）
配置无效: 配置文件版本 99 不受支持
运行时错误: Exception: OneLap login failed: user is not exists
```

同步中有失败时，退出码为 `1` 且 stdout 输出统计与逐条失败明细（单平台失败不影响其他平台）：

```
OneLap 获取: 3 个活动
本地判重跳过: 1
成功上传: 1
失败: 1

Strava: 成功 1 | 失败 1
Xingzhe: 成功 0 | 判重 1
Intervals.icu: 未启用
Outbase: 未启用

失败明细:
  - Strava: 2026-08-15 · 32.5km · 186m — DioException: Connection timed out
```

## JSON 输出模式（--json）

加 `--json` 后，stdout 输出结构化 JSON（替代人类可读文本），适合脚本 / cron / 自动化消费。结构与字段：

```json
{
  "fetched": 3,              // OneLap 拉取到的活动数
  "deduped": 1,              // 本地判重跳过（不算成功/失败）
  "success": 1,              // 本次实际成功上传数
  "failed": 1,               // 本次实际失败数
  "abortedReason": null,     // 非 null 时同步中止，如 "risk-control"（OneLap 风控）
  "failureReasons": [        // 失败原因的简单文本列表
    "上传失败 (a.fit): DioException timeout"
  ],
  "platforms": {
    "strava": {
      "success": 1,          // 该平台成功数
      "failed": 1,           // 该平台失败数
      "deduped": 0,          // 该平台判重跳过数
      "failures": [          // 失败活动明细
        {
          "fingerprint": "x",
          "date": "2026-08-15",   // 活动日期
          "distance": "32.5km",   // 距离
          "ascent": "186m",       // 爬升
          "error": "DioException: Connection timed out"
        }
      ]
    },
    "xingzhe":      { "success": 0, "failed": 0, "deduped": 1, "failures": [] },
    "intervalsIcu": { "success": 0, "failed": 0, "deduped": 0, "failures": [] },
    "outbase":      { "success": 0, "failed": 0, "deduped": 0, "failures": [] }
  },
  "syncedAt": "2026-08-17T08:00:00.000Z"   // 本次同步时间（ISO 8601）
}
```

脚本判断逻辑（配合退出码）：

```bash
wansync sync -c app-config.json --json > result.json
code=$?
if [ $code -eq 0 ]; then
  echo "全部同步成功"
elif [ $code -eq 1 ]; then
  echo "有失败: $(python3 -c 'import json;print(json.load(open("result.json"))["failureReasons"])')"
else
  echo "出错（exit $code），stderr 中有原因"
fi
```

注意：`--json` 只影响 stdout 的结果输出；参数 / 配置 / 运行时错误仍走 stderr，格式与文本模式一致。

## 仓库结构

```
packages/
  sync_core/    纯 Dart 同步核心（App 与 CLI 共用，无 Flutter 依赖）
  wansync_cli/  CLI：参数解析 + 装配 + 输出
```

## 设计文档

- [CLI 设计](docs/superpowers/specs/2026-08-16-wansync-cli-design.md)

## 开发

```bash
cd packages/sync_core && dart pub get && dart test
cd packages/wansync_cli && dart pub get && dart test
```

> 注意：配置 JSON 包含账号密码与 token，请妥善保管，不要提交到仓库。
