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
```

退出码：`0` 无失败 · `1` 有失败 · `2` 参数错误 · `3` 配置无效 · `4` 运行时错误。

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
