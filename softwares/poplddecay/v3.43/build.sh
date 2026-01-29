#!/bin/bash
set -e
source config/global.env
source config/platform.env

# 1. 进入源码目录
cd "${SRC_PATH}"
log_info "Current directory: $(pwd)"

# 2. 环境适配：处理 zlib 路径 (macOS 特有)
CXXFLAGS="-O3 -Wall"
LDFLAGS="-lz"

if [ "$OS_TYPE" == "macos" ]; then
    # macOS 的 zlib 不在标准路径，需要 Homebrew 指向
    if [ -d "/opt/homebrew/opt/zlib" ]; then
        ZLIB_ROOT="/opt/homebrew/opt/zlib"
    else
        ZLIB_ROOT="/usr/local/opt/zlib"
    fi
    CXXFLAGS="$CXXFLAGS -I${ZLIB_ROOT}/include"
    LDFLAGS="-L${ZLIB_ROOT}/lib $LDFLAGS"
fi

# 3. 执行编译
# 根据 Makefile 里的 PopLDdecay_SOURCES = src/LD_Decay.cpp
log_info "Compiling PopLDdecay for ${OS_TYPE}-${ARCH_TYPE}..."

if [ "$OS_TYPE" == "windows" ]; then
    # Windows 下建议静态链接 zlib，防止缺少 dll
    g++ $CXXFLAGS src/LD_Decay.cpp -o "PopLDdecay${EXE_EXT}" -static $LDFLAGS -lpthread
else
    g++ $CXXFLAGS src/LD_Decay.cpp -o "PopLDdecay${EXE_EXT}" $LDFLAGS -lpthread
fi

# 4. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
mv "PopLDdecay${EXE_EXT}" "${INSTALL_PREFIX}/bin/"

# 5. 编译附属工具 (如果有)
if [ -d "bin" ]; then
    log_info "Copying additional scripts..."
    cp -r bin/* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true
fi

log_info "Build completed: ${INSTALL_PREFIX}/bin/PopLDdecay${EXE_EXT}"
