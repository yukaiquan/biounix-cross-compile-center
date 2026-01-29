#!/bin/bash
set -e

# --- 关键修复：加载配置和工具函数 ---
# 这样脚本内部才能识别 log_info
source config/global.env
source config/platform.env
if [ -f "scripts/utils.sh" ]; then
    source scripts/utils.sh
fi

SOFT_NAME=$1
SOFT_VER=$2

# 加载软件特定的依赖定义
DEPS_FILE="softwares/${SOFT_NAME}/${SOFT_VER}/deps.env"
if [ -f "$DEPS_FILE" ]; then
    source "$DEPS_FILE"
else
    # 如果没定义，设置默认值防止变量为空
    DEPS_APT="build-essential zlib1g-dev"
    DEPS_BREW="zlib"
    DEPS_MSYS2="mingw-w64-x86_64-gcc mingw-w64-x86_64-zlib"
fi

log_info "Installing dependencies for ${OS_TYPE}..."

case "$OS_TYPE" in
  linux)
    sudo apt-get update
    sudo apt-get install -y $DEPS_APT
    ;;
  macos)
    brew install $DEPS_BREW
    ;;
  windows)
    # 只要是在 MSYS2 环境下运行，这个命令就能找到
    pacman -S --noconfirm --needed $DEPS_MSYS2
    ;;
esac
