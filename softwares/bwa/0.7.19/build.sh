#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
cd "${SRC_PATH}"
log_info "Building bwa in: $(pwd)"

# 3. 基础编译参数（基于原版 Makefile）
export CFLAGS="-g -Wall -Wno-unused-function -O3"
export DFLAGS="-DHAVE_PTHREAD -DUSE_MALLOC_WRAPPERS"
export LIBS="-lm -lz -lpthread"

# 4. Windows 特殊处理
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Building for Windows (MSYS2)..."
    
    # Windows 静态编译
    export CFLAGS="${CFLAGS} -static"
    
    # Windows 使用 gcc
    export CC="gcc"
    
    # 创建 Windows 兼容头文件
    cat > kutils_win.h << 'EOF'
#ifndef KUTILS_WIN_H
#define KUTILS_WIN_H

#ifdef _WIN32

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <time.h>

// 替代 sys/resource.h
typedef struct {
    long tv_sec;
    long tv_usec;
} rusage_t;

#ifndef RUSAGE_SELF
#define RUSAGE_SELF 0
#endif

static inline int getrusage(int who, rusage_t *r) {
    // Windows 上简化实现
    if (r) {
        r->tv_sec = 0;
        r->tv_usec = 0;
    }
    return 0;
}

// 替代 lrand48/srand48
static inline long lrand48(void) {
    return (long)((rand() << 16) ^ rand());
}

static inline void srand48(long seed) {
    srand((unsigned int)seed);
}

#endif // _WIN32

#endif // KUTILS_WIN_H
EOF
    
    # 注入兼容头文件到源文件
    for src in utils.c bntseq.c; do
        if [ -f "$src" ]; then
            # 在第一个 #include 之后插入兼容头
            sed -i '/^#include/a #include "kutils_win.h"' "$src" 2>/dev/null || true
        fi
    done
    
    # Windows 不需要 -lrt
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
fi

# 5. 非 Windows 平台适配
if [ "$OS_TYPE" != "windows" ]; then
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
            elif [ -d "/usr/local/opt/zlib" ]; then
                export CFLAGS="${CFLAGS} -I/usr/local/opt/zlib/include"
                export LDFLAGS="-L/usr/local/opt/zlib/lib"
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
            
            if [ "${ARCH_TYPE}" == "arm64" ]; then
                if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
                    export CC="aarch64-linux-gnu-gcc"
                    export AR="aarch64-linux-gnu-ar"
                fi
            fi
            ;;
    esac
fi

# 6. 编译
log_info "Compiler: ${CC}"
log_info "CFLAGS: ${CFLAGS}"

log_info "Running: make clean"
make clean 2>/dev/null || true

log_info "Running: make -j${MAKE_JOBS}"
make -j${MAKE_JOBS}

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f bwa${EXE_EXT} "${INSTALL_PREFIX}/bin/"

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bwa${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bwa installed to ${INSTALL_PREFIX}/bin/"
