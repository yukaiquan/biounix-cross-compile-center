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

# 3. 针对 Windows 的环境深度适配
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying Windows-specific fixes for GFortran and OpenBLAS..."

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

    # B. 源码清洗
    sed -i 's/#include <openblas_config.h>/\/\/ disabled/g' src/gemma.cpp
    sed -i 's/-isystem\/usr\/local\/opt\/openblas\/include//g' Makefile

    # C. 设置变量：显式包含 MinGW 的库路径以确保找到 libgfortran
    FIX_HEADER="$(pwd)/mingw_gemma_fix.h"
    # 添加 -Wno-maybe-uninitialized 解决 GCC15 报错
    export CXXFLAGS="-O3 -include ${FIX_HEADER} -I/mingw64/include/openblas -std=gnu++11 -Wno-unused-result -Wno-maybe-uninitialized -Wno-unknown-pragmas"
    
    # 关键：在 LDFLAGS 中加入 MinGW 库的搜索路径
    export LDFLAGS="-static -static-libgcc -static-libstdc++ -L/mingw64/lib"
    
    # 指定链接库，注意顺序：数学库通常需要放在最后，系统库紧随其后
    export LIBS="-lopenblas -lgfortran -lquadmath -lgsl -lgslcblas -lz -lws2_32"
    MAKE_VARS="WITH_OPENBLAS=1 SYS=MINGW"
else
    # Mac/Linux 设置 (保持不变)
    MAKE_VARS="WITH_OPENBLAS=1"
fi

# 4. 平台适配 (Mac/Linux)
if [ "$OS_TYPE" == "macos" ]; then
    [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
    export CXXFLAGS="-O3 -I${BP}/opt/gsl/include -I${BP}/opt/openblas/include"
    export LDFLAGS="-L${BP}/opt/gsl/lib -L${BP}/opt/openblas/lib"
fi

if [ "$OS_TYPE" == "linux" ]; then
    export CXXFLAGS="-O3 -static"
    export LDFLAGS="-static"
    if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
        export CXX="aarch64-linux-gnu-g++"
        export AR="aarch64-linux-gnu-ar"
        export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
    fi
fi

# 5. 执行编译
log_info "Cleaning and Compiling..."
make clean || true

# 关键：通过命令行参数强制覆盖 Makefile 的 CXXFLAGS, LDFLAGS, LIBS
log_info "Running make -j${MAKE_JOBS} ${MAKE_VARS}"
make -j${MAKE_JOBS} ${MAKE_VARS} \
    CXX="${CXX:-g++}" \
    CXXFLAGS="${CXXFLAGS}" \
    LDFLAGS="${LDFLAGS}" \
    LIBS="${LIBS}"

# 6. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
[ -f "bin/gemma" ] && cp -f bin/gemma "${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"
[ -f "gemma" ] && cp -f gemma "${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "GEMMA Build Successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found!"
    exit 1
fi
