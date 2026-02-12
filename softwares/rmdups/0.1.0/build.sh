#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building rmdups in: $(pwd)"
log_info "Source directory contents:"
ls -la

# 3. 安装/升级 Rust 工具链（需要 edition 2024）
log_info "Installing/updating Rust..."
rustup install stable
rustup default stable
rustup update stable

# 检查 Rust 版本
RUST_VERSION=$(rustc --version | awk '{print $2}')
log_info "Rust version: $RUST_VERSION"

# 4. Rust 静态编译
log_info "Building rmdups Release..."

# 设置静态链接标志
export RUSTFLAGS="-C target-feature=+crt-static"

if [ "$OS_TYPE" == "linux" ]; then
    # Linux 静态编译
    if [ "${ARCH_TYPE}" == "arm64" ]; then
        # ARM64 静态编译
        cargo build --release --target aarch64-unknown-linux-gnu
        mkdir -p "${INSTALL_PREFIX}/bin"
        cp target/aarch64-unknown-linux-gnu/release/rmdups "${INSTALL_PREFIX}/bin/"
    else
        # x86_64 静态编译
        cargo build --release --target x86_64-unknown-linux-gnu
        mkdir -p "${INSTALL_PREFIX}/bin"
        cp target/x86_64-unknown-linux-gnu/release/rmdups "${INSTALL_PREFIX}/bin/"
    fi
elif [ "$OS_TYPE" == "macos" ]; then
    # macOS 编译（动态链接，静态编译复杂）
    cargo build --release
    mkdir -p "${INSTALL_PREFIX}/bin"
    cp target/release/rmdups "${INSTALL_PREFIX}/bin/"
elif [ "$OS_TYPE" == "windows" ]; then
    # Windows 编译
    cargo build --release --target x86_64-pc-windows-gnu
    mkdir -p "${INSTALL_PREFIX}/bin"
    cp target/x86_64-pc-windows-gnu/release/rmdups.exe "${INSTALL_PREFIX}/bin/"
fi

# 5. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/rmdups${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    log_info "Binary info:"
    file "$FINAL_BIN"
    ls -la "$FINAL_BIN"
else
    log_err "Build artifact not found: $FINAL_BIN"
    exit 1
fi
