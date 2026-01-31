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

# 3. 基础参数
MAKE_VARS="WITH_OPENBLAS=1"

# 4. 平台与架构适配
case "${OS_TYPE}" in
    "windows")
        log_info "Applying deep Windows-POSIX compatibility patches..."

        # A. 创建功能完善的补丁头文件 (mingw_gemma_fix.h)
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

/* 1. 基础类型与宏补全 */
typedef unsigned int uint;
#ifndef __STRING
#define __STRING(x) #x
#endif

/* 2. 模拟 POSIX mkdir (Windows 的 _mkdir 只有一个参数) */
#define mkdir(path, mode) _mkdir(path)

/* 3. 模拟 strndup */
static inline char* strndup(const char* s, size_t n) {
    size_t len = strnlen(s, n);
    char* new_str = (char*)malloc(len + 1);
    if (!new_str) return NULL;
    new_str[len] = '\0';
    return (char*)memcpy(new_str, s, len);
}

/* 4. 模拟 kill 和 getpid (用于信号处理) */
#define kill(pid, sig) raise(sig)

/* 5. 模拟浮点异常处理 (MinGW 不支持，直接跳过) */
#define FE_INVALID    0x01
#define FE_DIVBYZERO  0x04
#define FE_OVERFLOW   0x08
#define FE_UNDERFLOW  0x10
static inline int feenableexcept(int excepts) { (void)excepts; return 0; }
static inline int fedisableexcept(int excepts) { (void)excepts; return 0; }

/* 6. 安全的 asprintf 实现 */
static inline int asprintf(char **strp, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int len = _vscprintf(fmt, ap);
    va_end(ap);
    if (len < 0) return -1;
    *strp = (char *)malloc(len + 1);
    if (!*strp) return -1;
    va_start(ap, fmt);
    len = vsnprintf(*strp, len + 1, fmt, ap);
    va_end(ap);
    return len;
}

#ifdef __cplusplus
}
#endif
#endif
#endif
EOF

        # B. 源码预处理：移除对 <openblas_config.h> 的直接引用
        # 在 MSYS2 中，只需包含 <cblas.h>
        sed -i 's/#include <openblas_config.h>/\/\/ disabled/g' src/gemma.cpp

        # C. 注入编译标志
        # -Wno-error=nodiscard: 忽略 eof() 返回值警告
        # -include: 强制包含我们的 Shim
        # -I: 增加 OpenBLAS 头文件搜索路径
        FIX_HEADER="$(pwd)/mingw_gemma_fix.h"
        export CXXFLAGS="-O3 -include ${FIX_HEADER} -I/mingw64/include/openblas -std=gnu++11 -Wno-unused-result -Wno-error=nodiscard"
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        
        # 强制指定链接库：Windows 静态链接 OpenBLAS 需要连带 gfortran 和系统底层库
        export LIBS="-lopenblas -lgsl -lgslcblas -lgfortran -lquadmath -lz -lws2_32"
        MAKE_VARS="${MAKE_VARS} SYS=MINGW"
        ;;

    "macos")
        log_info "Configuring for macOS..."
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CXXFLAGS="-O3 -I${BP}/opt/gsl/include -I${BP}/opt/openblas/include"
        export LDFLAGS="-L${BP}/opt/gsl/lib -L${BP}/opt/openblas/lib"
        ;;

    "linux")
        log_info "Configuring for Linux..."
        export CXXFLAGS="-O3 -static"
        export LDFLAGS="-static"
        if [ "${ARCH_TYPE}" == "arm64" ] && [[ "$(uname -m)" != "aarch64" ]]; then
            export CXX="aarch64-linux-gnu-g++"
            export AR="aarch64-linux-gnu-ar"
            export LDFLAGS="-static -L/usr/lib/aarch64-linux-gnu"
        fi
        ;;
esac

# 5. 执行编译
log_info "Cleaning..."
make clean || true

log_info "Running: make -j${MAKE_JOBS} ${MAKE_VARS}"
# 通过变量传递，强行覆盖 Makefile 内部定义的 CXXFLAGS 和 LIBS
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
    log_info "Build successful: $FINAL_BIN"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found!"
    exit 1
fi
