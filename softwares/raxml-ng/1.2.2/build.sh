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

# --- 4. 源码深度补丁 (针对 Windows/GCC15 的终极手术) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying deep compatibility patches for Windows..."

    # 修复 A: 注入 asprintf 模拟实现
    if [ -f "src/common.h" ]; then
        log_info "Injecting asprintf shim into src/common.h..."
        # 使用 cat <<'EOF' (带单引号) 防止 shell 扩展变量内容
        cat >> src/common.h <<'EOF'

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

    # 修复 B: 在 CMakeLists.txt 顶层强制注入编译器标志 (避开命令行引号坑)
    log_info "Injecting compiler flags into CMakeLists.txt..."
    sed -i '2i set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fpermissive -Wno-error=int-conversion -Wno-error=stringop-truncation -Wno-error=format-truncation")' CMakeLists.txt
    sed -i '2i set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-int-conversion -Wno-error=int-conversion -Wno-error=stringop-truncation")' CMakeLists.txt
    
    # 修复 C: 提升所有子模块的 CMake 策略要求
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +

    # 修复 D: 解决子模块中的 errno 变量名冲突 (递归替换 libs 目录下所有相关文件)
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) \
        -exec sed -i 's/\berrno\b/pll_errno/g' {} +

    # 修复 E: 修复 Bison 函数原型声明冲突
    find libs -name "parse_utree.y" -exec sed -i 's/extern int pll_utree_parse();/struct pll_unode_s; int pll_utree_parse(struct pll_unode_s * tree);/g' {} +
    find libs -name "parse_rtree.y" -exec sed -i 's/extern int pll_rtree_parse();/struct pll_rnode_s; int pll_rtree_parse(struct pll_rnode_s * tree);/g' {} +
fi

# 5. 初始化 CMake 参数 (去除 CMAKE_CXX_FLAGS，改用内部注入)
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
# 此时如果失败，make 会输出更清晰的错误信息
make -j${MAKE_JOBS} || make

# 7. 整理产物
mkdir -p "${INSTALL_PREFIX}/bin"
find . -name "raxml-ng${EXE_EXT}" -type f -exec cp -f {} "${INSTALL_PREFIX}/bin/" \;

# 8. 验证
FINAL_BIN="${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
if [ -f "$FINAL_BIN" ]; then
    log_info "Build successful!"
    file "$FINAL_BIN" || true
else
    log_err "Binary not found!"
    exit 1
fi
