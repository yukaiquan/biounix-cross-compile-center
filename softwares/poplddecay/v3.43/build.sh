#!/bin/bash
set -e

# 1. 环境加载
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 目录定位
cd "${SRC_PATH}"
[[ -d "src" ]] && cd src

# 3. 强制变量（防呆）
if [[ "$(uname -s)" == *"MSYS"* || "$(uname -s)" == *"MINGW"* ]]; then
    OS_TYPE="windows"
    EXE_EXT=".exe"
fi

log_info "BUILDING FOR: $OS_TYPE"

# 4. 编译逻辑
if [ "$OS_TYPE" == "windows" ]; then
    # 强制生成带后缀的独特文件名
    OUTPUT_NAME="PopLDdecay_WINDOWS_X64.exe"
    log_info "Compiling Windows binary: $OUTPUT_NAME"
    g++ -g -O2 -Wall -static -static-libgcc -static-libstdc++ LD_Decay.cpp -o "$OUTPUT_NAME" -lz -lpthread -lws2_32
    
    # 现场打印指纹（这会显示在 GitHub 日志里）
    echo "FINGERPRINT: $(file $OUTPUT_NAME)"
    
    mkdir -p "${INSTALL_PREFIX}/bin"
    cp -f "$OUTPUT_NAME" "${INSTALL_PREFIX}/bin/"
    # 放入一个文本文件作为 100% 的身份证明
    echo "This package was built on a Windows Runner at $(date)" > "${INSTALL_PREFIX}/bin/VERIFY_PLATFORM.txt"

elif [ "$OS_TYPE" == "linux" ]; then
    OUTPUT_NAME="PopLDdecay_LINUX_X64"
    g++ -g -O2 -Wall -static LD_Decay.cpp -o "$OUTPUT_NAME" -lz -lpthread
    mkdir -p "${INSTALL_PREFIX}/bin"
    cp -f "$OUTPUT_NAME" "${INSTALL_PREFIX}/bin/"
else
    # Mac
    g++ -g -O2 -Wall LD_Decay.cpp -o PopLDdecay -lz -lpthread
    mkdir -p "${INSTALL_PREFIX}/bin"
    cp -f PopLDdecay "${INSTALL_PREFIX}/bin/"
fi
