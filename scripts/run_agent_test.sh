#!/bin/bash
# run_agent_test.sh — 通用 nanobot agent 测试聊天脚本
#
# 用法:
#   ./scripts/run_agent_test.sh -m "你好，测试测试"
#   ./scripts/run_agent_test.sh -m "回顾一下" -w /path/to/workspace -c /path/to/config.json
#   ./scripts/run_agent_test.sh -m "你好" --backup    # 测试后自动 git commit 备份聊天记录
#   ./scripts/run_agent_test.sh --last                # 查看上次聊天记录
#   ./scripts/run_agent_test.sh --list-sessions       # 列出所有 session 文件
#
# 默认配置指向 self-evolve 实验工作目录:
#   /home/admin/projects/2026/experiment-workspace/nanobot-profiles/self-evolve-workspace/origin-nanobot-oblivionis-001

set -euo pipefail

# ─── 颜色 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'

# ─── 默认路径 ───
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NANOBOT_DIR="$(dirname "$SCRIPT_DIR")"

DEFAULT_WORKSPACE="/home/admin/projects/2026/experiment-workspace/nanobot-profiles/self-evolve-workspace/origin-nanobot-oblivionis-001/workspace"
DEFAULT_CONFIG="/home/admin/projects/2026/experiment-workspace/nanobot-profiles/self-evolve-workspace/origin-nanobot-oblivionis-001/config.json"
CONFIG_DIR="/home/admin/projects/2026/experiment-workspace/nanobot-profiles/self-evolve-workspace/origin-nanobot-oblivionis-001"

# ─── 参数解析 ───
MSG=""
WORKSPACE="$DEFAULT_WORKSPACE"
CONFIG="$DEFAULT_CONFIG"
SESSION_ID="cli:direct"
DO_BACKUP=false
DO_LAST=false
DO_LIST=false
DO_COPY=false
COPY_NAME=""
NO_MARKDOWN=false

usage() {
    cat <<EOF
${CYAN}nanobot agent 测试脚本${RESET}

用法: $(basename "$0") [选项]

选项:
  -m, --message MSG       发送消息（必需，除非用 --last/--list-sessions）
  -w, --workspace PATH    工作目录 (默认: self-evolve 实验目录)
  -c, --config PATH       配置文件路径 (默认: self-evolve config.json)
  -s, --session ID        Session ID (默认: cli:direct)
  --backup                测试后 git commit 备份聊天记录
  --last                  查看上次聊天记录（cli_direct.jsonl 最后 20 行）
  --list-sessions         列出所有 session 文件
  --copy NAME             复制配置目录为新的测试实例（NAME 为子目录名）
  --no-markdown           不使用 markdown 渲染
  -h, --help              显示帮助

示例:
  $(basename "$0") -m "你好，测试测试"
  $(basename "$0") -m "回顾一下" --backup
  $(basename "$0") -m "测试 copy" --copy test-liminal
  $(basename "$0") --last
  $(basename "$0") --list-sessions
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--message)   MSG="$2"; shift 2 ;;
        -w|--workspace) WORKSPACE="$2"; shift 2 ;;
        -c|--config)    CONFIG="$2"; shift 2 ;;
        -s|--session)   SESSION_ID="$2"; shift 2 ;;
        --backup)       DO_BACKUP=true; shift ;;
        --last)         DO_LAST=true; shift ;;
        --list-sessions) DO_LIST=true; shift ;;
        --copy)         DO_COPY=true; COPY_NAME="$2"; shift 2 ;;
        --no-markdown)  NO_MARKDOWN=true; shift ;;
        -h|--help)      usage ;;
        *) echo -e "${RED}未知参数: $1${RESET}"; usage ;;
    esac
done

# ─── 辅助函数 ───

info()  { echo -e "${CYAN}[INFO]${RESET} $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
fail()  { echo -e "${RED}[FAIL]${RESET} $*"; exit 1; }

activate_venv() {
    cd "$NANOBOT_DIR"
    if [ ! -d ".venv" ]; then
        fail ".venv not found in $NANOBOT_DIR — 请先初始化 Python 环境"
    fi
    source .venv/bin/activate
    if ! command -v nanobot &> /dev/null; then
        fail "nanobot 命令不可用 — 请检查 .venv 是否正确安装"
    fi
}

# ─── 列出 sessions ───
if $DO_LIST; then
    activate_venv
    SESSIONS_DIR="$WORKSPACE/sessions"
    if [ ! -d "$SESSIONS_DIR" ]; then
        fail "sessions 目录不存在: $SESSIONS_DIR"
    fi
    echo -e "${CYAN}Sessions in ${SESSIONS_DIR}:${RESET}"
    echo ""
    ls -lht "$SESSIONS_DIR" | head -20
    echo ""
    echo -e "${DIM}总计 $(ls "$SESSIONS_DIR" | wc -l) 个文件${RESET}"
    exit 0
fi

# ─── 查看上次聊天记录 ───
if $DO_LAST; then
    activate_venv
    SESSIONS_DIR="$WORKSPACE/sessions"
    FILE="$SESSIONS_DIR/cli_direct.jsonl"
    if [ ! -f "$FILE" ]; then
        fail "cli_direct.jsonl 不存在: $FILE"
    fi
    LINES=$(wc -l < "$FILE")
    echo -e "${CYAN}上次聊天记录 (${FILE})${RESET}"
    echo -e "${DIM}共 ${LINES} 行，显示最后 20 行:${RESET}"
    echo ""
    tail -20 "$FILE" | while IFS= read -r line; do
        ROLE=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('role','?'))" 2>/dev/null || echo "?")
        case "$ROLE" in
            user)      COLOR="$GREEN" ;;
            assistant) COLOR="$CYAN" ;;
            tool)      COLOR="$DIM" ;;
            *)         COLOR="$RESET" ;;
        esac
        # 截断显示
        PREVIEW=$(echo "$line" | head -c 200)
        echo -e "  ${COLOR}[${ROLE}]${RESET} ${PREVIEW:0:180}"
    done
    exit 0
fi

# ─── 复制配置目录 ───
if $DO_COPY; then
    if [ -z "$COPY_NAME" ]; then
        fail "--copy 需要指定名称，如: --copy test-liminal"
    fi
    PARENT_DIR="$(dirname "$CONFIG_DIR")"
    NEW_DIR="${PARENT_DIR}/${COPY_NAME}"
    if [ -d "$NEW_DIR" ]; then
        warn "目标目录已存在: $NEW_DIR"
        read -rp "覆盖? (y/N) " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "取消"
            exit 0
        fi
        rm -rf "$NEW_DIR"
    fi
    info "复制 $CONFIG_DIR → $NEW_DIR ..."
    cp -r "$CONFIG_DIR" "$NEW_DIR"
    # 清空 sessions（新实例从干净状态开始）
    rm -f "$NEW_DIR/workspace/sessions/"*.jsonl 2>/dev/null || true
    # 更新当前脚本的路径指向
    WORKSPACE="$NEW_DIR/workspace"
    CONFIG="$NEW_DIR/config.json"
    CONFIG_DIR="$NEW_DIR"
    ok "已创建测试实例: $NEW_DIR"
    # 如果原目录有 git，新目录也初始化
    if [ -d "$CONFIG_DIR/.git" ]; then
        cd "$CONFIG_DIR"
        git checkout -b "test-${COPY_NAME}" 2>/dev/null || true
        ok "git 分支: test-${COPY_NAME}"
    fi
fi

# ─── 消息检查 ───
if [ -z "$MSG" ]; then
    fail "请用 -m 指定消息内容，或用 --last/--list-sessions"
fi

# ─── 环境检查 ───
activate_venv

# 验证路径存在
if [ ! -f "$CONFIG" ]; then
    fail "config 不存在: $CONFIG"
fi
if [ ! -d "$WORKSPACE" ]; then
    fail "workspace 不存在: $WORKSPACE"
fi

# ─── 执行 ───
MARKDOWN_FLAG="--markdown"
if $NO_MARKDOWN; then
    MARKDOWN_FLAG="--no-markdown"
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${CYAN} nanobot agent test${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
info "config:    $CONFIG"
info "workspace: $WORKSPACE"
info "session:   $SESSION_ID"
info "message:   $MSG"
echo ""

nanobot agent \
    -m "$MSG" \
    -c "$CONFIG" \
    -w "$WORKSPACE" \
    -s "$SESSION_ID" \
    $MARKDOWN_FLAG

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ─── 备份 ───
if $DO_BACKUP; then
    cd "$CONFIG_DIR"
    if [ -d ".git" ]; then
        git add -A
        TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
        git commit -m "test: agent chat backup at ${TIMESTAMP}" --allow-empty 2>/dev/null || true
        ok "聊天记录已备份到 git"
    else
        warn "未找到 .git，跳过备份。在 $CONFIG_DIR 下初始化 git 以启用自动备份。"
    fi
fi

ok "完成"
