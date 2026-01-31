#!/bin/bash
set -e

# 加载环境
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 进入源码目录 (作者代码在 src/ 目录下)
cd "${SRC_PATH}"
[[ -d "src" ]] && cd src

log_info "Start Compiling PopLDdecay for ${OS_TYPE}-${ARCH_TYPE}..."

# 1. 基础编译器定义
CXX="g++"
CXXFLAGS="-g -O2 -Wall"
LDFLAGS="-lz -lpthread"

# 2. 针对不同系统进行“死命令”适配
if [ "$OS_TYPE" == "macos" ]; then
    log_info "Applying macOS native build..."
    # Mac 不允许使用 -static
    # 自动探测 Homebrew zlib
    [ -d "/opt/homebrew/opt/zlib" ] && ZDIR="/opt/homebrew/opt/zlib" || ZDIR="/usr/local/opt/zlib"
    if [ -d "$ZDIR" ]; then
        CXXFLAGS="$CXXFLAGS -I${ZDIR}/include"
        LDFLAGS="-L${ZDIR}/lib $LDFLAGS"
    fi
elif [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows static build..."
    # Windows 必须静态链接，否则换台机器就报“缺少dll”
    CXXFLAGS="$CXXFLAGS -static -static-libgcc -static-libstdc++"
    LDFLAGS="$LDFLAGS -lws2_32"
elif [ "$OS_TYPE" == "linux" ]; then
    log_info "Applying Linux full-static build..."
    # 解决你说的“Linux缺失动态库”问题：强制全静态
    LDFLAGS="-static $LDFLAGS"
    # 如果是交叉编译 ARM
    if [ "$ARCH_TYPE" == "arm64" ] && [ "$(uname -m)" != "aarch64" ]; then
        CXX="aarch64-linux-gnu-g++"
    fi
fi

# 3. 执行编译 (直接学作者，针对核心 cpp 文件)
log_info "Exec: $CXX $CXXFLAGS LD_Decay.cpp -o PopLDdecay${EXE_EXT} $LDFLAGS"
$CXX $CXXFLAGS LD_Decay.cpp -o "PopLDdecay${EXE_EXT}" $LDFLAGS

# 4. 关键验证：在日志里直接打印结果格式
log_info "VERIFICATION: This file is currently:"
file "PopLDdecay${EXE_EXT}" || ls -l "PopLDdecay${EXE_EXT}"

# 5. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f "PopLDdecay${EXE_EXT}" "${INSTALL_PREFIX}/bin/"
# 拷贝作者自带的配套脚本
if [ -d "../bin" ]; then
    cp ../bin/* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true
fi

log_info "Success. Binary path: ${INSTALL_PREFIX}/bin/PopLDdecay${EXE_EXT}"
