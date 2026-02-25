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
    
    # 创建兼容头文件
    cat > kutils_win.h << 'EOF'
#ifndef KUTILS_WIN_H
#define KUTILS_WIN_H

#ifdef _WIN32

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>

typedef struct {
    long tv_sec;
    long tv_usec;
    long tv_maxrss;
} rusage_t;

#define RUSAGE_SELF 0

static inline int getrusage(int who, rusage_t *r) {
    (void)who;
    if (r) memset(r, 0, sizeof(rusage_t));
    return 0;
}

static inline long lrand48(void) {
    return (long)((rand() << 16) ^ rand());
}

static inline void srand48(long seed) {
    srand((unsigned int)seed);
}

#include <io.h>
#define fsync _commit

#endif
#endif
EOF
    
    # 修改源文件
    for file in utils.c bntseq.c; do
        [ -f "$file" ] || continue
        # 在开头插入
        sed -i '1i #include "kutils_win.h"' "$file"
        # 注释掉 sys/resource.h
        sed -i 's|#include <sys/resource.h>|// #include <sys/resource.h>|' "$file"
        log_info "Patched: $file"
    done
    
    # 清理
    make clean 2>/dev/null || true
    
    # 编译 - 使用完整的 CFLAGS
    log_info "Compiling..."
    make -j${MAKE_JOBS} \
        CC=gcc \
        CFLAGS="-g -Wall -Wno-unused-function -O3 -static -DHAVE_PTHREAD -DUSE_MALLOC_WRAPPERS -I." \
        LDFLAGS="-static -static-libgcc -static-libstdc++" \
        LIBS="-lm -lz -lpthread"
        
else
    # 非 Windows 平台
    export CFLAGS="-g -Wall -Wno-unused-function -O3"
    export LIBS="-lm -lz -lpthread"
    
    case "${OS_TYPE}" in
        "macos")
            log_info "Building for macOS..."
            [ -d "/opt/homebrew/opt/zlib" ] && export CFLAGS="${CFLAGS} -I/opt/homebrew/opt/zlib/include"
            [ "${ARCH_TYPE}" == "arm64" ] && export CFLAGS="${CFLAGS} -arch arm64"
            ;;
        
        "linux")
            log_info "Building for Linux..."
            export LIBS="${LIBS} -lrt"
            export LDFLAGS="-static"
            ;;
    esac
    
    make clean 2>/dev/null || true
    make -j${MAKE_JOBS}
fi

# 4. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
cp -f bwa${EXE_EXT} "${INSTALL_PREFIX}/bin/"

# 5. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/bwa${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found: $FINAL_BIN"
    exit 1
fi

log_info "bwa installed to ${INSTALL_PREFIX}/bin/"
