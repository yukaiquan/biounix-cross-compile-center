#!/bin/bash
set -e

# 1. 加载基础配置和工具函数 (修复 log_info 找不到的问题)
# 注意：脚本由根目录运行，所以使用相对路径或基于 BASE_DIR 的路径
if [ -f "scripts/utils.sh" ]; then
    source scripts/utils.sh
else
    # 备用方案：如果脚本是在当前目录执行，尝试加载同级或上级目录
    source "$(dirname "$0")/../../../scripts/utils.sh" || echo "Warning: utils.sh not found"
fi

source config/global.env
source config/platform.env

# 2. 检查 SRC_PATH (从 fetch_source.sh 传递过来的)
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH is not set or directory does not exist: '$SRC_PATH'"
fi

# 3. 进入源码目录
cd "${SRC_PATH}"
log_info "Building in directory: $(pwd)"

# 4. 环境适配：处理编译器和 zlib 路径
CXX="g++"
CXXFLAGS="-O3 -Wall"
LDFLAGS="-lz"

if [ "$OS_TYPE" == "macos" ]; then
    # macOS 的 zlib 不在标准路径，需要 Homebrew 指向
    if [ -d "/opt/homebrew/opt/zlib" ]; then
        ZLIB_ROOT="/opt/homebrew/opt/zlib"
    elif [ -d "/usr/local/opt/zlib" ]; then
        ZLIB_ROOT="/usr/local/opt/zlib"
    fi
    
    if [ -n "$ZLIB_ROOT" ]; then
        CXXFLAGS="$CXXFLAGS -I${ZLIB_ROOT}/include"
        LDFLAGS="-L${ZLIB_ROOT}/lib $LDFLAGS"
        log_info "Using macOS zlib from: $ZLIB_ROOT"
    fi
fi

# 5. 执行编译
log_info "Compiling PopLDdecay for ${OS_TYPE}-${ARCH_TYPE}..."

if [ "$OS_TYPE" == "windows" ]; then
    # Windows (MinGW/MSYS2) 下建议静态链接 zlib 和 libstdc++，方便分发
    log_info "Using static linking for Windows..."
    $CXX $CXXFLAGS src/LD_Decay.cpp -o "PopLDdecay${EXE_EXT}" -static $LDFLAGS -lpthread
else
    $CXX $CXXFLAGS src/LD_Decay.cpp -o "PopLDdecay${EXE_EXT}" $LDFLAGS -lpthread
fi

# 6. 整理产物到 dist 目录
mkdir -p "${INSTALL_PREFIX}/bin"
mv "PopLDdecay${EXE_EXT}" "${INSTALL_PREFIX}/bin/"

# 7. 拷贝附属工具 (软件自带的脚本)
if [ -d "bin" ]; then
    log_info "Copying additional scripts from bin/..."
    cp -r bin/* "${INSTALL_PREFIX}/bin/" 2>/dev/null || true
fi

log_info "Build success! Artifact: ${INSTALL_PREFIX}/bin/PopLDdecay${EXE_EXT}"
