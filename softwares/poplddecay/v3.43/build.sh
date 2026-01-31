#!/bin/bash
set -e

# 1. 环境加载
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 定位源码 (PopLDdecay 的源码在 src 下)
cd "${SRC_PATH}"
[[ -d "src" ]] && cd src

# 3. 再次强制校准 OS 变量 (防止某些环境下识别失效)
if [[ "$(uname -s)" == *"MSYS"* || "$(uname -s)" == *"MINGW"* ]]; then
    OS_TYPE="windows"
    EXE_EXT=".exe"
elif [[ "$(uname -s)" == "Darwin" ]]; then
    OS_TYPE="macos"
    EXE_EXT=""
else
    OS_TYPE="linux"
    EXE_EXT=""
fi

# 4. 设置标准输出文件名
# 这样无论在哪个系统，编译出来的都是 PopLDdecay 或 PopLDdecay.exe
BIN_NAME="PopLDdecay${EXE_EXT}"

log_info "Building standard binary: $BIN_NAME for $OS_TYPE"

# 5. 编译逻辑 (保持之前成功的静态链接参数)
if [ "$OS_TYPE" == "windows" ]; then
    g++ -g -O2 -Wall -static -static-libgcc -static-libstdc++ LD_Decay.cpp -o "$BIN_NAME" -lz -lpthread -lws2_32
elif [ "$OS_TYPE" == "linux" ]; then
    # Linux 采用全静态编译，解决“缺失动态库”问题
    if [ "$ARCH_TYPE" == "arm64" ] && [ "$(uname -m)" != "aarch64" ]; then
        aarch64-linux-gnu-g++ -g -O2 -Wall -static LD_Decay.cpp -o "$BIN_NAME" -lz -lpthread
    else
        g++ -g -O2 -Wall -static LD_Decay.cpp -o "$BIN_NAME" -lz -lpthread
    fi
else
    # Mac (不支持静态链接)
    g++ -g -O2 -Wall LD_Decay.cpp -o "$BIN_NAME" -lz -lpthread
fi

# 6. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f "$BIN_NAME" "${INSTALL_PREFIX}/bin/"

# 拷贝作者自带的配套脚本
if [ -d "../bin" ]; then
    cp ../bin/* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true
fi

log_info "Done. Binary: ${INSTALL_PREFIX}/bin/$BIN_NAME"
