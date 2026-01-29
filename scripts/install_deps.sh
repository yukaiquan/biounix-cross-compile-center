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
    if [ "${ARCH_TYPE}" == "arm64" ]; then
        # 安装 arm64 版本的 zlib 库
        sudo dpkg --add-architecture arm64
        sudo apt-get update
        sudo apt-get install -y zlib1g-dev:arm64 gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
    else
        sudo apt-get install -y build-essential zlib1g-dev
    fi
    ;;
  macos)
    brew install zlib
    ;;
  windows)
    pacman -S --noconfirm --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-zlib
    ;;
esac
