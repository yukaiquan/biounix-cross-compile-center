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
    if [ "${ARCH_TYPE}" == "arm64" ]; then
        log_info "Preparing ARM64 cross-compile environment..."
        sudo dpkg --add-architecture arm64
        sudo apt-get update
        sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu zlib1g-dev:arm64 libbz2-dev:arm64 liblzma-dev:arm64 libcurl4-gnutls-dev:arm64 libssl-dev:arm64 libncurses5-dev:arm64
    else
        sudo apt-get install -y build-essential zlib1g-dev
    fi
    ;;
  macos)
    brew update
    brew install zlib
    brew install $DEPS_BREW
    echo "/opt/homebrew/bin:/usr/local/bin" >> $GITHUB_PATH
    ;;
  windows)
    # pacman -S --noconfirm --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-zlib
    log_info "Updating MSYS2 database..."
    # --noconfirm: 不询问
    # --needed: 如果已经安装了就跳过
    # --disable-download-timeout: 尝试缓解网络慢的问题
    pacman -Sy --noconfirm

    log_info "Installing: $DEPS_MSYS2"
    # 核心修改：使用多次尝试下载，防止单次超时
    for i in {1..3}; do
        pacman -S --noconfirm --needed $DEPS_MSYS2 && break || sleep 5
    done
    ;;
esac
