#!/bin/bash
set -e

# 1. 环境加载
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 定位源码
cd "${SRC_PATH}"
[[ -d "src" ]] && cd src

# 3. 产物清理
BIN_NAME="LDBlockShow${EXE_EXT}"
rm -f "LDBlockShow" "LDBlockShow.exe"

log_info "Matrix Command -> OS: $OS_TYPE | ARCH: $ARCH_TYPE"

# 4. 根据 OS_TYPE 执行编译
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Building for Windows..."
    # Windows 交叉编译 - 使用 MinGW
    # 关键：需要静态链接 zlib
    g++ -O3 -Wall -static -static-libgcc -static-libstdc++ LDBlockShow.cpp -o "$BIN_NAME" -lz -lpthread -lws2_32

elif [ "$OS_TYPE" == "macos" ]; then
    log_info "Building for macOS..."
    [ -d "/opt/homebrew/opt/zlib" ] && ZDIR="/opt/homebrew/opt/zlib" || ZDIR="/usr/local/opt/zlib"
    if [ -d "$ZDIR" ]; then
        g++ -O3 -Wall -I${ZDIR}/include LDBlockShow.cpp -o "$BIN_NAME" -L${ZDIR}/lib -lz -lpthread
    else
        g++ -O3 -Wall LDBlockShow.cpp -o "$BIN_NAME" -lz -lpthread
    fi

else
    # Linux
    log_info "Building for Linux..."
    if [ "$ARCH_TYPE" == "arm64" ]; then
        log_info "Using ARM64 Cross-Compiler"
        aarch64-linux-gnu-g++ -O3 -Wall -static LDBlockShow.cpp -o "$BIN_NAME" -lz -lpthread
    else
        log_info "Using x64 Native Compiler"
        g++ -O3 -Wall -static LDBlockShow.cpp -o "$BIN_NAME" -lz -lpthread
    fi
fi

# 5. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
rm -f "${INSTALL_PREFIX}/bin/LDBlockShow" "${INSTALL_PREFIX}/bin/LDBlockShow.exe"
cp -f "$BIN_NAME" "${INSTALL_PREFIX}/bin/"

# 6. 验证
log_info "Final Verification in Runner:"
file "${INSTALL_PREFIX}/bin/$BIN_NAME"
