#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building fixfq (Rust) in: $(pwd)"

# 3. 安装 Rust (如果需要)
if ! command -v cargo &> /dev/null; then
    log_info "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# 4. 添加目标平台
if [ "$OS_TYPE" == "linux" ]; then
    # 静态链接需要 musl
    if [ "$TARGET" == "x86_64-unknown-linux-musl" ]; then
        rustup target add x86_64-unknown-linux-musl
    fi
elif [ "$OS_TYPE" == "windows" ]; then
    rustup target add x86_64-pc-windows-gnu
fi

# 5. 清理并构建
log_info "Building fixfq..."

if [ "$OS_TYPE" == "linux" ]; then
    if [ "$TARGET" == "x86_64-unknown-linux-musl" ]; then
        # 静态链接构建
        cargo build --release --target x86_64-unknown-linux-musl --locked
    else
        cargo build --release --locked
    fi
elif [ "$OS_TYPE" == "macos" ]; then
    cargo build --release --locked
elif [ "$OS_TYPE" == "windows" ]; then
    export CARGO_BUILD_RUSTFLAGS="-C target-feature=+crt-static"
    cargo build --release --target x86_64-pc-windows-gnu --locked
fi

# 6. 安装产物
mkdir -p "${INSTALL_PREFIX}/bin"

if [ "$OS_TYPE" == "windows" ]; then
    cp target/x86_64-pc-windows-gnu/release/fixfq.exe "${INSTALL_PREFIX}/bin/"
    FINAL_BIN="${INSTALL_PREFIX}/bin/fixfq.exe"
elif [ "$OS_TYPE" == "linux" ]; then
    if [ "$TARGET" == "x86_64-unknown-linux-musl" ]; then
        cp target/x86_64-unknown-linux-musl/release/fixfq "${INSTALL_PREFIX}/bin/"
        FINAL_BIN="${INSTALL_PREFIX}/bin/fixfq"
    else
        cp target/release/fixfq "${INSTALL_PREFIX}/bin/"
        FINAL_BIN="${INSTALL_PREFIX}/bin/fixfq"
    fi
else
    cp target/release/fixfq "${INSTALL_PREFIX}/bin/"
    FINAL_BIN="${INSTALL_PREFIX}/bin/fixfq"
fi

# 7. 验证
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN"
    ls -la "$FINAL_BIN"
    
    # 验证版本
    "$FINAL_BIN" --version || true
else
    log_err "Build artifact not found: $FINAL_BIN"
    exit 1
fi
