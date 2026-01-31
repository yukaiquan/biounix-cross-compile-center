#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid"
fi
cd "${SRC_PATH}"
log_info "Building GEMMA in: $(pwd)"

# 3. 环境适配
case "${OS_TYPE}" in
    "windows")
        log_info "Applying Windows FULL-STATIC patches..."

        # A. 创建 Shim 头文件 (保持之前的修复)
        cat > mingw_gemma_fix.h <<'EOF'
#ifndef _MINGW_GEMMA_FIX_H
#define _MINGW_GEMMA_FIX_H
#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <process.h>
#include <signal.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef unsigned int uint;
#ifndef __STRING
#define __STRING(x) #x
#endif
#ifndef OPENBLAS_VERSION
#define OPENBLAS_VERSION "0.3.x-msys2"
#endif
#define mkdir(path, mode) _mkdir(path)
static inline char* strndup(const char* s, size_t n) {
    size_t len = strnlen(s, n);
    char* new_str = (char*)malloc(len + 1);
    if (!new_str) return NULL;
    new_str[len] = '\0';
    return (char*)memcpy(new_str, s, len);
}
#define kill(pid, sig) raise(sig)
#define getpid() _getpid()
static inline int feenableexcept(int e) { (void)e; return 0; }
static inline int fedisableexcept(int e) { (void)e; return 0; }
static inline int asprintf(char **strp, const char *fmt, ...) {
    va_list ap, ap2;
    va_start(ap, fmt);
    va_copy(ap2, ap);
    int len = _vscprintf(fmt, ap);
    va_end(ap);
    if (len < 0) { va_end(ap2); return -1; }
    *strp = (char *)malloc((size_t)len + 1);
    if (!*strp) { va_end(ap2); return -1; }
    len = vsnprintf(*strp, (size_t)len + 1, fmt, ap2);
    va_end(ap2);
    return len;
}
#ifdef __cplusplus
}
#endif
#endif
#endif
EOF

        # B. 源码清理：移除 Makefile 里的干扰
        sed -i 's/#include <openblas_config.h>/\/\/ disabled/g' src/gemma.cpp
        sed -i 's/-isystem\/usr\/local\/opt\/openblas\/include//g' Makefile

        # C. 强制静态库点名 (解决 libgsl-28.dll 报错的核心)
        # 通过 -l:filename 语法，强制链接器去读 .a 文件而不是 .dll.a
        FIX_HEADER="$(pwd)/mingw_gemma_fix.h"
        export CXXFLAGS="-O3 -include ${FIX_HEADER} -I/mingw64/include/openblas -std=gnu++11 -Wno-unused-result -Wno-maybe-uninitialized"
        
        # 链接顺序极其重要：静态库必须按照依赖关系排列
        # 我们直接指定 .a 文件名，确保不链接动态库
        export LIBS="-l:libopenblas.a -l:libgsl.a -l:libgslcblas.a -l:libgfortran.a -l:libquadmath.a -lz -lws2_32 -lpthread"
        export LDFLAGS="-static -static-libgcc -static-libstdc++ -L/mingw64/lib"
        
        MAKE_VARS="WITH_OPENBLAS=1 SYS=MINGW"
        ;;

    "macos")
        log_info "Configuring for macOS..."
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CXXFLAGS="-O3 -I${BP}/opt/gsl/include -I${BP}/opt/openblas/include"
        export LDFLAGS="-L${BP}/opt/gsl/lib -L${BP}/opt/openblas/lib"
        MAKE_VARS="WITH_OPENBLAS=1"
        ;;

    "linux")
        log_info "Configuring for Linux..."
        export CXXFLAGS="-O3 -static"
        export LDFLAGS="-static"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            export CXX="aarch64-linux-gnu-g++"
            export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
        fi
        MAKE_VARS="WITH_OPENBLAS=1"
        ;;
esac

# 4. 执行编译
log_info "Cleaning and Compiling..."
make clean || true

# 关键：手动传递所有变量。注意 LIBS 在命令行最后传递，以覆盖 Makefile 内部逻辑
log_info "Running: make ${MAKE_VARS}"
make -j${MAKE_JOBS} ${MAKE_VARS} \
    CXXFLAGS="${CXXFLAGS}" \
    LDFLAGS="${LDFLAGS}" \
    LIBS="${LIBS}"

# 5. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
[ -f "bin/gemma" ] && cp -f bin/gemma "${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"
[ -f "gemma" ] && cp -f gemma "${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"

# 6. 验证（在日志中确认是否还有 DLL 依赖）
log_info "Verifying dependencies of gemma${EXE_EXT}..."
if [ "$OS_TYPE" == "windows" ]; then
    # 使用 objdump 查看是否还残留动态库引用
    objdump -p "${INSTALL_PREFIX}/bin/gemma${EXE_EXT}" | grep "DLL Name" || echo "No DLL dependencies found!"
fi

log_info "Build success: ${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"
