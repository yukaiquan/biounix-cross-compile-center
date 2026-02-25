#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bwa in: $(pwd)"

# 3. Windows 特殊处理
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Building for Windows (MSYS2)..."
    
    # 方法1: 修改源文件，替换 sys/resource.h
    log_info "Patching source files for Windows..."
    
    # 备份并替换 sys/resource.h
    for file in utils.c bntseq.c; do
        if [ -f "$file" ]; then
            # 注释掉 sys/resource.h 并添加兼容头
            sed -i 's|#include <sys/resource.h>|// #include <sys/resource.h>  // removed for Windows|g' "$file"
        fi
    done
    
    # 添加兼容头到 utils.c 开头（在第一个 #include 之后）
    sed -i '/^#include/a #include <stdlib.h>' utils.c
    sed -i '/^#include/a #include <time.h>' utils.c
    
    # 清理并使用自定义 CFLAGS 编译
    make clean 2>/dev/null || true
    
    # Windows CFLAGS
    WIN_CFLAGS="-g -Wall -Wno-unused-function -O3 -static -DHAVE_PTHREAD -DUSE_MALLOC_WRAPPERS"
    WIN_LDFLAGS="-static -static-libgcc -static-libstdc++"
    
    log_info "Compiling with custom CFLAGS..."
    make -j${MAKE_JOBS} \
        CC=gcc \
        CFLAGS="${WIN_CFLAGS}" \
        LDFLAGS="${WIN_LDFLAGS}" \
        LIBS="-lm -lz -lpthread"
        
else
    # 4. 非 Windows 平台
    export CFLAGS="-g -Wall -Wno-unused-function -O3"
    export LIBS="-lm -lz -lpthread"
    
    case "${OS_TYPE}" in
        "macos")
            log_info "Building for macOS..."
            if command -v clang &>/dev/null; then
                export CC="clang"
            else
                export CC="gcc"
            fi
            
            if [ -d "/opt/homebrew/opt/zlib" ]; then
                export CFLAGS="${CFLAGS} -I/opt/homebrew/opt/zlib/include"
                export LDFLAGS="-L/opt/homebrew/opt/zlib/lib"
            fi
            
            if [ "${ARCH_TYPE}" == "arm64" ]; then
                export CFLAGS="${CFLAGS} -arch arm64"
            fi
            ;;
        
        "linux")
            log_info "Building for Linux..."
            export LIBS="${LIBS} -lrt"
            export LDFLAGS="-static"
            
            if command -v clang &>/dev/null; then
                export CC="clang"
            else
                export CC="gcc"
            fi
            ;;
    esac
    
    make clean 2>/dev/null || true
    make -j${MAKE_JOBS}
fi

# 5. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f bwa${EXE_EXT} "${INSTALL_PREFIX}/bin/"

# 6. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bwa${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bwa installed to ${INSTALL_PREFIX}/bin/"
