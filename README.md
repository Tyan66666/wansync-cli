# WanSync CLI

把 [Onelap-Strava-GoGoGo](https://github.com/Anomaly-Lap/Onelap-Strava-GoGoGo)（WanSync App）的同步机制做成跨平台终端 CLI：导入 App 导出的配置 JSON，即可在服务器 / 终端 / 骁龙 845 手机（Ubuntu）上无人值守同步 OneLap 活动到 Strava / Xingzhe / Intervals.icu / Outbase。

**零认证流程**：所有凭据来自 App 导出的配置文件，CLI 不做任何 OAuth / cookie 获取。

## 快速开始

```bash
# 编译单文件二进制（Linux / macOS / Windows / ARM64 各平台各自编译）
dart compile exe packages/wansync_cli/bin/wansync.dart -o wansync

# 导入 App 导出的配置 JSON 并同步
./wansync sync --config app-config.json

# 只同步部分平台 / 覆盖回看天数 / JSON 输出
./wansync sync -c app-config.json --platform strava,xingzhe --lookback 7
./wansync sync -c app-config.json --json

# 坐标转换覆盖：强制开启 / 强制关闭（默认用配置 sync.gcjCorrectionEnabled）
./wansync sync -c app-config.json --gcj-correction
./wansync sync -c app-config.json --no-gcj-correction
```

退出码：`0` 无失败 · `1` 有失败 · `2` 参数错误 · `3` 配置无效 · `4` 运行时错误。

## 获取二进制（按你的设备选一种）

**方式 A：GitHub Actions 下载（推荐，无需本地装 Dart）**

把仓库推到 GitHub 后，CI 会自动编译 4 个平台产物并作为 artifact 上传：

| artifact 名 | 适用设备 |
|---|---|
| `wansync-linux-x64` | 普通 Linux 服务器 / x64 电脑 |
| `wansync-linux-arm64` | **骁龙 845 手机（Ubuntu）**、树莓派、ARM 盒子 |
| `wansync-macos-arm64` | Mac（Apple Silicon） |
| `wansync-windows-x64` | Windows |

下载后解压得到单个可执行文件，直接拷贝到设备上。

**方式 B：在目标设备上自己编译**

```bash
# 在手机 Ubuntu / 服务器上（需先装 Dart SDK）
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
> 例如 macOS 上编的（Mach-O）不能拷到 Linux 手机上；x64 编的不能拷到 ARM 设备上。
> 手机场景务必用方式 A 的 `wansync-linux-arm64` 或方式 B 在手机上直接编。

## 在骁龙 845 手机（Ubuntu）上运行

```bash
# 1. 把二进制和配置放到手机（adb 或 U 盘均可）
#    配置 = App「设置 → 导出配置」生成的 JSON 文件
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

`--config` 指向 **App「设置 → 导出配置」生成的 JSON**，也可手工编写。仓库根目录附有 `config.json.example`（带完整注释的模板），**复制后填入真实值即可直接使用——配置支持 JSONC 注释（`//` 与 `/* */`），无需删除注释**。结构如下：

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
| `xingzhe` / `outbase` | 需先在 App 中登录（获得 sessionId）再导出；sessionId 过期后需在 App 重新登录导出 |
| `--platform` | 可临时覆盖 `uploadTo*` 开关，不修改配置文件 |
| `--gcj-correction` / `--no-gcj-correction` | 临时覆盖 `sync.gcjCorrectionEnabled`（GCJ-02 → WGS-84 坐标转换），不修改配置文件 |

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
