#!/bin/bash
set -e

# --- 关键修复：加载配置和工具函数 ---
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
        log_info "Installing native ARM64 dependencies..."
        sudo apt-get install -y zlib1g-dev libbz2-dev liblzma-dev || true
    else
        sudo apt-get install -y build-essential zlib1g-dev
    fi
    
    # 安装 Rust 工具链
    if [ "$NEED_RUSTUP" == "yes" ]; then
        log_info "Installing Rust toolchain..."
        curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
        source "$HOME/.cargo/env"
        rustup default stable
    fi
    ;;
  macos)
    brew update
    brew install zlib
    brew install $DEPS_BREW
    echo "/opt/homebrew/bin:/usr/local/bin" >> $GITHUB_PATH
    
    # 安装 Rust 工具链
    if [ "$NEED_RUSTUP" == "yes" ]; then
        log_info "Installing Rust toolchain..."
        curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
        source "$HOME/.cargo/env"
        rustup default stable
    fi
    ;;
  windows)
    log_info "Updating MSYS2 database..."
    pacman -Sy --noconfirm

    log_info "Installing: $DEPS_MSYS2"
    for i in {1..3}; do
        pacman -S --noconfirm --needed $DEPS_MSYS2 && break || sleep 5
    done
    
    # 安装 Rust 工具链
    if [ "$NEED_RUSTUP" == "yes" ]; then
        log_info "Installing Rust toolchain..."
        export RUSTUP_HOME="/c/Users/runneradmin/.rustup"
        export CARGO_HOME="/c/Users/runneradmin/.cargo"
        curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
        # rustup 已自动配置 PATH，不需要手动 source env
        export PATH="$CARGO_HOME/bin:$PATH"
        rustup default stable
    fi
    ;;
esac
