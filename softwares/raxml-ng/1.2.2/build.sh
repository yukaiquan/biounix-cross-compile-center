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

# --- 4. 源码深度手术 (针对 Windows/GCC15 的终极补丁) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying high-level compatibility patches for Windows..."

    # 修复 A: 解决 asprintf 在 Windows 缺失的问题
    # 直接在 src/common.h 中注入 asprintf 的实现，这是解决该报错最彻底的方法
    if [ -f "src/common.h" ]; then
        log_info "Injecting asprintf shim into src/common.h..."
        cat >> src/common.h <<EOF

/* RAXML-NG WINDOWS COMPATIBILITY SHIM */
#ifdef _WIN32
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
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
#endif
EOF
    fi

    # 修复 B: 解决 pll_utree_parse 和 pll_rtree_parse 的函数原型冲突
    find libs -name "parse_utree.y" -exec sed -i 's/extern int pll_utree_parse();/struct pll_unode_s; int pll_utree_parse(struct pll_unode_s * tree);/g' {} +
    find libs -name "parse_rtree.y" -exec sed -i 's/extern int pll_rtree_parse();/struct pll_rnode_s; int pll_rtree_parse(struct pll_rnode_s * tree);/g' {} +

    # 修复 C: 解决子模块中的 errno 变量名冲突
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) \
        -exec sed -i 's/\berrno\b/pll_errno/g' {} +

    # 修复 D: 强制提升所有 CMakeLists.txt 的版本要求
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +

    # 修复 E: 屏蔽编译警告
    MY_EXTRA_FLAGS="-fpermissive -Wno-error=int-conversion -Wno-error=stringop-truncation -Wno-error=format-truncation"
fi

# 5. 初始化 CMake 参数
# 使用 -DCMAKE_CXX_FLAGS 将参数强行注入
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5"

if [ -n "$MY_EXTRA_FLAGS" ]; then
    CMAKE_OPTS="$CMAKE_OPTS -DCMAKE_CXX_FLAGS='$MY_EXTRA_FLAGS' -DCMAKE_C_FLAGS='$MY_EXTRA_FLAGS'"
fi

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
# 此时如果失败，make 会输出更清晰的错误信息
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
