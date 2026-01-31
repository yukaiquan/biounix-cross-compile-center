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

# 3. 准备基础参数
# GEMMA 默认使用 OpenBLAS
MAKE_VARS="WITH_OPENBLAS=1"

# 4. 平台与架构适配
case "${OS_TYPE}" in
    "windows")
        log_info "Applying Windows compatibility patches for GEMMA..."

        # A. 创建 Windows 专属补丁头文件
        cat > mingw_gemma_fix.h <<'EOF'
#ifndef _MINGW_GEMMA_FIX_H
#define _MINGW_GEMMA_FIX_H
#ifdef _WIN32
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* 1. 修复 uint 未定义错误 */
typedef unsigned int uint;

/* 2. 修复 GLIBC 特有的 __STRING 宏缺失 */
#ifndef __STRING
#define __STRING(x) #x
#endif

/* 3. 兼容 OpenBLAS 头文件路径 */
/* MSYS2 的 OpenBLAS 配置文件可能在 openblas/ 目录下 */
#endif
#endif
EOF

        # B. 注入补丁并强制链接
        # 核心：-include 注入补丁，-I 指向 OpenBLAS 头文件目录
        # 注意：MSYS2 的 openblas 头文件通常在 /mingw64/include/openblas
        export CXXFLAGS="-O3 -include $(pwd)/mingw_gemma_fix.h -I/mingw64/include/openblas"
        export LDFLAGS="-static -static-libgcc -static-libstdc++"
        
        # Windows 下静态链接 OpenBLAS 通常需要补全 gfortran 和系统库
        # 注入到 MAKE_VARS 里的变量会覆盖 Makefile 的定义
        MAKE_VARS="${MAKE_VARS} SYS=MINGW"
        # 强制指定静态链接库顺序，防止 undefined reference
        export LIBS="-lopenblas -lgfortran -lquadmath -lgsl -lgslcblas -lz -lws2_32"
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
# 关键：手动传递 CXXFLAGS 和 LIBS 以覆盖 Makefile 内部的硬编码
make -j${MAKE_JOBS} ${MAKE_VARS} \
    CXX="${CXX:-g++}" \
    CXXFLAGS="${CXXFLAGS}" \
    LDFLAGS="${LDFLAGS}" \
    LIBS="${LIBS}"

# 6. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
# GEMMA 编译完可能在 bin/gemma 或根目录下
if [ -f "bin/gemma" ]; then
    cp -f bin/gemma "${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"
elif [ -f "gemma" ]; then
    cp -f gemma "${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"
fi

# 7. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/gemma${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build Successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found!"
    exit 1
fi
