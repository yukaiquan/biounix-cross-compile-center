#!/bin/bash
set -e

# 1. 环境加载
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 定位源码
cd "${SRC_PATH}"
# 保存原始路径用于复制 bin 目录
ORIGIN_DIR=$(pwd)

log_info "Original directory: ${ORIGIN_DIR}"
log_info "Files in directory: $(ls -la | head -20)"

# 进入 src 子目录编译（LDBlockShow.cpp 在 src/ 下）
if [ -d "src" ] && [ -f "src/LDBlockShow.cpp" ]; then
    cd src
    log_info "Changed to src directory: $(pwd)"
fi

# 确认当前目录有 LDBlockShow.cpp
if [ ! -f "LDBlockShow.cpp" ]; then
    log_err "LDBlockShow.cpp not found in $(pwd)"
    log_err "Files in current directory:"
    ls -la
    exit 1
fi

# 3. 产物清理
BIN_NAME="LDBlockShow${EXE_EXT}"
rm -f "LDBlockShow" "LDBlockShow.exe"

log_info "Matrix Command -> OS: $OS_TYPE | ARCH: $ARCH_TYPE"

# 4. 先复制整个 bin 目录（保留原有辅助工具）
mkdir -p "${INSTALL_PREFIX}/bin"
if [ -d "${ORIGIN_DIR}/bin" ]; then
    log_info "Copying original bin directory..."
    cp -rf "${ORIGIN_DIR}/bin/"* "${INSTALL_PREFIX}/bin/"
fi

# 5. 编译主程序 (使用官方 make.sh 的编译参数)
# 官方: g++ -std=c++11 -g -O2 LDBlockShow.cpp -lm -lc -lz -o ../bin/LDBlockShow
CXX_FLAGS="-std=c++11 -O3 -Wall"
LIBS="-lm -lc -lz"

if [ "$OS_TYPE" == "windows" ]; then
    log_info "Building for Windows..."
    # Windows 交叉编译 - 添加 Windows 专用库
    g++ ${CXX_FLAGS} -static -static-libgcc -static-libstdc++ LDBlockShow.cpp -o "$BIN_NAME" ${LIBS} -lpthread -lws2_32

elif [ "$OS_TYPE" == "macos" ]; then
    log_info "Building for macOS..."
    [ -d "/opt/homebrew/opt/zlib" ] && ZDIR="/opt/homebrew/opt/zlib" || ZDIR="/usr/local/opt/zlib"
    if [ -d "$ZDIR" ]; then
        g++ ${CXX_FLAGS} -I${ZDIR}/include LDBlockShow.cpp -o "$BIN_NAME" -L${ZDIR}/lib ${LIBS} -lpthread
    else
        g++ ${CXX_FLAGS} LDBlockShow.cpp -o "$BIN_NAME" ${LIBS} -lpthread
    fi

else
    # Linux
    log_info "Building for Linux..."
    if [ "$ARCH_TYPE" == "arm64" ]; then
        log_info "Using ARM64 Cross-Compiler"
        aarch64-linux-gnu-g++ ${CXX_FLAGS} -static LDBlockShow.cpp -o "$BIN_NAME" ${LIBS} -lpthread
    else
        log_info "Using x64 Native Compiler"
        g++ ${CXX_FLAGS} -static LDBlockShow.cpp -o "$BIN_NAME" ${LIBS} -lpthread
    fi
fi

# 6. 复制编译好的主程序（覆盖或不覆盖）
rm -f "${INSTALL_PREFIX}/bin/LDBlockShow" "${INSTALL_PREFIX}/bin/LDBlockShow.exe"
cp -f "$BIN_NAME" "${INSTALL_PREFIX}/bin/"

# 7. 验证
log_info "Final Verification in Runner:"
ls -la "${INSTALL_PREFIX}/bin/"
file "${INSTALL_PREFIX}/bin/$BIN_NAME"
