#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码目录
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH is invalid"
fi
cd "${SRC_PATH}"

# 3. 精准定位 CMake 根目录
if [ ! -f "CMakeLists.txt" ]; then
    log_info "Locating real CMake root..."
    CMAKEROOT=$(find . -maxdepth 3 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$CMAKEROOT" ] && cd "$CMAKEROOT"
fi
log_info "Final build root: $(pwd)"

# --- 4. 源码深度手术 (针对 Windows/MinGW 最终补丁) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying robust compatibility patches for Windows..."

    # 修复 A: 以“预置”方式注入 asprintf 实现，并带上独立保护宏
    if [ -f "src/common.h" ]; then
        log_info "Injecting asprintf shim to the TOP of src/common.h..."
        cat > shim.h <<'EOF'
#ifndef _ASPRINTF_SHIM_H
#define _ASPRINTF_SHIM_H
#ifdef _WIN32
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#ifdef __cplusplus
extern "C" {
#endif
static inline int asprintf(char **strp, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int len = vsnprintf(NULL, 0, fmt, ap);
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
        # 将 shim 放到文件最前面
        cat shim.h src/common.h > src/common.h.new
        mv src/common.h.new src/common.h
        rm shim.h
    fi

    # 修复 B: 在 CMakeLists.txt 内部注入参数，解决 GCC 15 兼容性
    # 采用更简单的 sed 命令避免引号转义问题
    sed -i '2i set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fpermissive")' CMakeLists.txt
    sed -i '3i set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-int-conversion")' CMakeLists.txt
    
    # 修复 C: 提升子模块 CMake 版本要求
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +

    # 修复 D: 递归替换所有子模块中的 errno 变量名
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) \
        -exec sed -i 's/\berrno\b/pll_errno/g' {} +

    # 修复 E: 修复 Bison 函数原型声明冲突
    find libs -name "parse_utree.y" -exec sed -i 's/extern int pll_utree_parse();/struct pll_unode_s; int pll_utree_parse(struct pll_unode_s * tree);/g' {} +
    find libs -name "parse_rtree.y" -exec sed -i 's/extern int pll_rtree_parse();/struct pll_rnode_s; int pll_rtree_parse(struct pll_rnode_s * tree);/g' {} +
fi

# 5. 初始化 CMake 参数
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5"

case "${OS_TYPE}" in
    "windows")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
        GENERATOR="MSYS Makefiles"
        ;;
    "macos")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CMAKE_PREFIX_PATH="${BP}:${CMAKE_PREFIX_PATH}"
        ;;
    "linux")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=ON"
        GENERATOR="Unix Makefiles"
        ;;
esac

# 6. 执行构建
rm -rf build_dir && mkdir build_dir && cd build_dir
log_info "Running CMake..."
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}

log_info "Running Make..."
# 使用单线程编译以获得清晰的错误输出，如果失败则停止
make -j${MAKE_JOBS} || make

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
find . -name "raxml-ng${EXE_EXT}" -type f -exec cp -f {} "${INSTALL_PREFIX}/bin/" \;

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "RAxML-NG build SUCCESSFUL!"
    file "$FINAL_BIN" || true
else
    log_err "RAxML-NG binary not found!"
    exit 1
fi
