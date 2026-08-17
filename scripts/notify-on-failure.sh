#!/usr/bin/env bash
#
# WanSync CLI — 失败通知示例脚本
#
# 演示 --json + 退出码的完整用法：
#   - 退出码 0        → 全部成功，静默退出（或写一条 OK 日志）
#   - 退出码 1        → 同步中有失败：解析 result.json 输出失败明细，发通知
#   - 退出码 2/3/4    → 参数/配置/运行时错误：stderr 有原因，同样发通知
#
# 用法:
#   ./scripts/notify-on-failure.sh -c /path/to/app-config.json [wansync 的其他参数...]
#   WANSYNC_NOTIFY_URL=https://ntfy.sh/your-topic ./scripts/notify-on-failure.sh -c app-config.json
#
# 环境变量（可选）:
#   WANSYNC_BIN         wansync 二进制路径（默认: 与本脚本同级的 ../packages/wansync_cli/dist/wansync）
#   WANSYNC_NOTIFY_URL  通知 URL。设置后用 curl POST 一条 JSON 通知
#                        （兼容 ntfy.sh；Telegram/企业微信等可自行改 curl 部分）
#   WANSYNC_LOG_DIR     日志目录（默认: ~/.wansync/logs）
#
# 依赖: bash >= 4, curl（仅设置了 WANSYNC_NOTIFY_URL 时需要）

set -u

# ---- 参数解析（透传 wansync 参数，仅识别 -c/--config 用于日志命名）----
CONFIG_PATH=""
SYNC_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      CONFIG_PATH="${2:-}"
      SYNC_ARGS+=("$1" "$2")
      shift 2
      ;;
    --config=*)
      CONFIG_PATH="${1#*=}"
      SYNC_ARGS+=("$1")
      shift
      ;;
    *)
      SYNC_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$CONFIG_PATH" ]]; then
  echo "用法: $0 -c <config.json> [wansync 参数...]" >&2
  exit 2
fi

# ---- 路径与目录 ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WANSYNC_BIN="${WANSYNC_BIN:-$SCRIPT_DIR/../packages/wansync_cli/dist/wansync}"
LOG_DIR="${WANSYNC_LOG_DIR:-$HOME/.wansync/logs}"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT_FILE="$LOG_DIR/result-$STAMP.json"
LOG_FILE="$LOG_DIR/sync-$STAMP.log"

if [[ ! -x "$WANSYNC_BIN" ]]; then
  echo "找不到 wansync 二进制: $WANSYNC_BIN（用 WANSYNC_BIN 指定路径）" >&2
  exit 4
fi

# ---- 执行同步（stdout → JSON 文件，stderr → 日志）----
"$WANSYNC_BIN" sync "${SYNC_ARGS[@]}" --json > "$RESULT_FILE" 2> "$LOG_FILE"
CODE=$?

notify() { # $1 = 标题, $2 = 正文
  if [[ -n "${WANSYNC_NOTIFY_URL:-}" ]]; then
    curl -sf -X POST "$WANSYNC_NOTIFY_URL" \
      -H "Content-Type: text/plain" \
      -d "$1"$'\n\n'"$2" > /dev/null 2>&1 || echo "[notify] 通知发送失败" >&2
  fi
}

case $CODE in
  0)
    # 全部成功 —— 静默（cron 友好）；想看可以打开下面这行
    # cat "$RESULT_FILE"
    exit 0
    ;;
  1)
    # 同步中有失败 —— 从 JSON 提取失败明细
    echo "[$(date '+%F %T')] 同步完成但存在失败 (exit 1)，明细见 $RESULT_FILE" >&2
    if command -v jq > /dev/null 2>&1; then
      echo "失败原因:" >&2
      jq -r '.failureReasons[] | "  - " + .' "$RESULT_FILE" >&2
      echo "失败活动:" >&2
      jq -r '.platforms | to_entries[] | .key as $p | .value.failures[] |
             "  - \($p): \(.date) \(.distance) \(.ascent) — \(.error // "未知错误")"' \
        "$RESULT_FILE" >&2
      notify "WanSync 同步有失败 (exit 1)" \
        "$(jq -r '"成功 \(.success)，失败 \(.failed)（fetched \(.fetched)）\n" + (.failureReasons | join("\n"))' "$RESULT_FILE")"
    else
      echo "（未安装 jq，完整 JSON 见 $RESULT_FILE）" >&2
      notify "WanSync 同步有失败 (exit 1)" "详见 $RESULT_FILE"
    fi
    ;;
  *)
    # 2/3/4 —— 参数/配置/运行时错误，原因在 stderr 日志里
    echo "[$(date '+%F %T')] wansync 出错 (exit $CODE)，日志: $LOG_FILE" >&2
    notify "WanSync 运行出错 (exit $CODE)" "$(cat "$LOG_FILE")"
    ;;
esac

# 出错时也以非 0 退出，方便上层 cron/脚本继续判断
exit "$CODE"
