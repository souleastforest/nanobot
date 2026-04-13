#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PARENT_DIR"

# 检查虚拟环境是否存在
if [ ! -d ".venv" ]; then
    echo "Error: .venv not found in $PARENT_DIR"
    exit 1
fi

# 激活环境
source .venv/bin/activate

# 检查 nanobot 是否可用
if ! command -v nanobot &> /dev/null; then
    echo "Error: nanobot command not found"
    exit 1
fi

# Avoid shell-exported Claude/Anthropic vars from contaminating nanobot's own provider config.
unset ANTHROPIC_API_KEY
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_BASE_URL
unset ANTHROPIC_MODEL
unset ANTHROPIC_SMALL_FAST_MODEL
unset ANTHROPIC_DEFAULT_SONNET_MODEL
unset ANTHROPIC_DEFAULT_OPUS_MODEL
unset ANTHROPIC_DEFAULT_HAIKU_MODEL

# 执行
nanobot gateway --workspace nanobot-profiles/.nanobot-oblivionis-001/workspace --config ./nanobot-profiles/.nanobot-oblivionis-001/config.json