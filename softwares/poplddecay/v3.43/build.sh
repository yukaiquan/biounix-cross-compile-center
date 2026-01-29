#!/bin/bash
set -e
source config/global.env
source config/platform.env
source scripts/utils.sh

cd "${SRC_PATH}"

# 设置编译器
CXX="g++"
if [ "$OS_TYPE" == "windows" ]; then
    # 确保在 Windows 下强制使用静态链接
    # -static: 静态链接所有库
    # -static-libgcc -static-libstdc++: 专门针对 GCC 的标准库静态链接
    CXXFLAGS="-O3 -Wall -static -static-libgcc -static-libstdc++"
    LDFLAGS="-lz -lpthread"
    log_info "Building for Windows with static linking..."
elif [ "$OS_TYPE" == "macos" ]; then
    # macOS 处理 zlib 路径 (保持不变)
    [ -d "/opt/homebrew/opt/zlib" ] && ZDIR="/opt/homebrew/opt/zlib" || ZDIR="/usr/local/opt/zlib"
    CXXFLAGS="-O3 -Wall -I${ZDIR}/include"
    LDFLAGS="-L${ZDIR}/lib -lz -lpthread"
else
    # Linux
    CXXFLAGS="-O3 -Wall"
    LDFLAGS="-lz -lpthread"
fi

log_info "Compiling PopLDdecay on ${OS_TYPE}..."
$CXX $CXXFLAGS src/LD_Decay.cpp -o "PopLDdecay${EXE_EXT}" $LDFLAGS

mkdir -p "${INSTALL_PREFIX}/bin"
# 使用 cp 而不是 mv，方便调试
cp "PopLDdecay${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
