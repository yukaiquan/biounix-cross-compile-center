#!/bin/bash
set -e

# 1. 环境识别
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入目录
cd "${SRC_PATH}"

# 3. 设置变量
CXX="g++"
CXXFLAGS="-O3 -Wall -std=c++11"
LDFLAGS=""

log_info "Build Task: OS=$OS_TYPE, ARCH=$ARCH_TYPE"

# 4. 根据平台强制配置
if [ "$OS_TYPE" == "linux" ]; then
    # Linux 全静态编译
    log_info "Configuring Linux Full-Static..."
    LDFLAGS="-static -lz -lpthread"
    if [ "$ARCH_TYPE" == "arm64" ]; then
        CXX="aarch64-linux-gnu-g++"
        LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu -lz -lpthread"
    fi
elif [ "$OS_TYPE" == "windows" ]; then
    # Windows MinGW 静态编译
    log_info "Configuring Windows Native Static..."
    CXXFLAGS="$CXXFLAGS -static -static-libgcc -static-libstdc++"
    LDFLAGS="-lz -lws2_32"
elif [ "$OS_TYPE" == "macos" ]; then
    # Mac 动态编译 (Mac 不支持 -static)
    log_info "Configuring macOS Native..."
    [ -d "/opt/homebrew/opt/zlib" ] && ZDIR="/opt/homebrew/opt/zlib" || ZDIR="/usr/local/opt/zlib"
    if [ -d "$ZDIR" ]; then
        CXXFLAGS="$CXXFLAGS -I${ZDIR}/include"
        LDFLAGS="-L${ZDIR}/lib -lz"
    else
        LDFLAGS="-lz"
    fi
fi

# 5. 执行编译
$CXX $CXXFLAGS src/LD_Decay.cpp -o "PopLDdecay${EXE_EXT}" $LDFLAGS

# 6. 整理
mkdir -p "${INSTALL_PREFIX}/bin"
cp "PopLDdecay${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
if [ -d "bin" ]; then cp -r bin/* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true; fi

log_info "Build successful: $(file PopLDdecay${EXE_EXT})"
