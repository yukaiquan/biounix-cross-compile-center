#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building rmduprs in: $(pwd)"
log_info "Source directory contents:"
ls -la

# 3. 设置 Rust 环境
log_info "Setting up Rust environment..."

if [ "$OS_TYPE" == "windows" ]; then
    # Windows MSYS2 特殊处理
    export RUSTUP_HOME="/c/Users/runneradmin/.rustup"
    export CARGO_HOME="/c/Users/runneradmin/.cargo"
    export PATH="$CARGO_HOME/bin:$PATH"
    export CC="gcc"
    export CXX="g++"
    log_info "Windows Rust path: $CARGO_HOME/bin"
else
    source "$HOME/.cargo/env" 2>/dev/null || true
fi

# 4. 安装/升级 Rust 工具链
log_info "Installing/updating Rust..."
rustup install stable 2>/dev/null || true
rustup default stable 2>/dev/null || true
rustup update stable 2>/dev/null || true

# 检查 Rust 版本
RUST_VERSION=$(rustc --version 2>/dev/null | awk '{print $2}')
if [ -n "$RUST_VERSION" ]; then
    log_info "Rust version: $RUST_VERSION"
else
    log_err "Rust not found in PATH"
    exit 1
fi

# 5. Rust 静态编译
log_info "Building rmduprs Release..."

# 设置静态链接标志
export RUSTFLAGS="-C target-feature=+crt-static"

if [ "$OS_TYPE" == "linux" ]; then
    # Linux 静态编译
    if [ "${ARCH_TYPE}" == "arm64" ]; then
        # ARM64 静态编译
        cargo build --release --target aarch64-unknown-linux-gnu
        mkdir -p "${INSTALL_PREFIX}/bin"
        cp target/aarch64-unknown-linux-gnu/release/rmduprs "${INSTALL_PREFIX}/bin/"
    else
        # x86_64 静态编译
        cargo build --release --target x86_64-unknown-linux-gnu
        mkdir -p "${INSTALL_PREFIX}/bin"
        cp target/x86_64-unknown-linux-gnu/release/rmduprs "${INSTALL_PREFIX}/bin/"
    fi
elif [ "$OS_TYPE" == "macos" ]; then
    # macOS 编译
    cargo build --release
    mkdir -p "${INSTALL_PREFIX}/bin"
    cp target/release/rmduprs "${INSTALL_PREFIX}/bin/"
elif [ "$OS_TYPE" == "windows" ]; then
    # Windows 编译
    cargo build --release --target x86_64-pc-windows-gnu
    mkdir -p "${INSTALL_PREFIX}/bin"
    cp target/x86_64-pc-windows-gnu/release/rmduprs.exe "${INSTALL_PREFIX}/bin/"
fi

# 6. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/rmduprs${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    log_info "Binary info:"
    file "$FINAL_BIN"
    ls -la "$FINAL_BIN"
else
    log_err "Build artifact not found: $FINAL_BIN"
    exit 1
fi
