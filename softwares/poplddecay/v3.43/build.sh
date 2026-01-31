#!/bin/bash
set -e

# 1. 环境加载 (加载 global 和 platform，获取 matrix 传进来的变量)
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 定位源码
cd "${SRC_PATH}"
[[ -d "src" ]] && cd src

# 3. 产物清理 (物理隔离，确保当前目录没有旧的二进制)
BIN_NAME="PopLDdecay${EXE_EXT}"
rm -f "PopLDdecay" "PopLDdecay.exe"

log_info "Matrix Command -> OS: $OS_TYPE | ARCH: $ARCH_TYPE"

# 4. 根据 OS_TYPE 执行编译 (直接使用从 Workflow 传进来的变量)
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Building for Windows..."
    g++ -O3 -Wall -static -static-libgcc -static-libstdc++ LD_Decay.cpp -o "$BIN_NAME" -lz -lpthread -lws2_32

elif [ "$OS_TYPE" == "macos" ]; then
    log_info "Building for macOS..."
    # macOS 自动处理，不加 static
    [ -d "/opt/homebrew/opt/zlib" ] && ZDIR="/opt/homebrew/opt/zlib" || ZDIR="/usr/local/opt/zlib"
    if [ -d "$ZDIR" ]; then
        g++ -O3 -Wall -I${ZDIR}/include LD_Decay.cpp -o "$BIN_NAME" -L${ZDIR}/lib -lz -lpthread
    else
        g++ -O3 -Wall LD_Decay.cpp -o "$BIN_NAME" -lz -lpthread
    fi

else
    # 统一视为 Linux (包括 x64 和 arm64 交叉编译)
    log_info "Building for Linux..."
    if [ "$ARCH_TYPE" == "arm64" ]; then
        log_info "Using ARM64 Cross-Compiler"
        aarch64-linux-gnu-g++ -O3 -Wall -static LD_Decay.cpp -o "$BIN_NAME" -lz -lpthread
    else
        log_info "Using x64 Native Compiler"
        g++ -O3 -Wall -static LD_Decay.cpp -o "$BIN_NAME" -lz -lpthread
    fi
fi

# 5. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# 先清空目标目录，防止 Linux 的文件留给 Mac
rm -f "${INSTALL_PREFIX}/bin/PopLDdecay" "${INSTALL_PREFIX}/bin/PopLDdecay.exe"
cp -f "$BIN_NAME" "${INSTALL_PREFIX}/bin/"

# 6. 现场打印格式（在 GitHub 日志里一眼看出对错）
log_info "Final Verification in Runner:"
file "${INSTALL_PREFIX}/bin/$BIN_NAME"
