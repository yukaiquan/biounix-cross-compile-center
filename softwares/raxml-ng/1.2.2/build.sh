#!/bin/bash
set -e

# 1. 加载配置
source config/global.env
source config/platform.env
[ -f "scripts/utils.sh" ] && source scripts/utils.sh

# 2. 进入源码目录
if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    log_err "SRC_PATH invalid"
fi
cd "${SRC_PATH}"

# 3. 精准定位 CMake 根目录
if [ ! -f "CMakeLists.txt" ]; then
    CMAKEROOT=$(find . -maxdepth 3 -name "CMakeLists.txt" -exec grep -l "project" {} + | head -n 1 | xargs dirname)
    [ -n "$CMAKEROOT" ] && cd "$CMAKEROOT"
fi

# --- 4. 源码补丁 (针对 Windows 稳定性的终极修正) ---
if [ "$OS_TYPE" == "windows" ]; then
    log_info "Applying stability patches for Windows..."

    # 修复 A: 注入全能 Shim
    # 关键：posix_memalign 直接映射为 malloc，避开 _aligned_malloc 导致的 free() 崩溃
    cat > mingw_shim.h <<'EOF'
#ifndef _MINGW_RAXML_SHIM_H
#define _MINGW_RAXML_SHIM_H
#ifdef _WIN32
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdarg.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t u_int32_t;

/* asprintf shim */
static inline int asprintf(char **strp, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    int len = vsnprintf(NULL, 0, fmt, ap); va_end(ap);
    if (len < 0) return -1;
    *strp = (char *)malloc(len + 1);
    if (!*strp) return -1;
    va_start(ap, fmt);
    len = vsnprintf(*strp, len + 1, fmt, ap); va_end(ap);
    return len;
}

/* 稳定版内存对齐模拟：直接使用 malloc 配合标准 free */
static inline int posix_memalign(void **memptr, size_t alignment, size_t size) {
    (void)alignment;
    *memptr = malloc(size);
    return (*memptr) ? 0 : 12;
}

/* sysinfo 模拟 */
struct sysinfo { uint64_t totalram; int mem_unit; };
static inline int sysinfo(struct sysinfo* i) {
    MEMORYSTATUSEX s; s.dwLength = sizeof(s);
    GlobalMemoryStatusEx(&s);
    i->totalram = s.ullTotalPhys;
    i->mem_unit = 1;
    return 0;
}

/* sysconf 模拟 */
#define _SC_NPROCESSORS_ONLN 1
static inline long sysconf(int n) {
    (void)n;
    SYSTEM_INFO s; GetSystemInfo(&s);
    return s.dwNumberOfProcessors;
}

#define realpath(a, b) _fullpath((b), (a), 260)

/* getrusage 模拟 */
#define RUSAGE_SELF 0
struct rusage { struct {long tv_sec; long tv_usec;} ru_utime, ru_stime; long ru_maxrss; };
static inline int getrusage(int w, struct rusage *r) { 
    (void)w; memset(r, 0, sizeof(struct rusage)); return 0; 
}

#ifdef __cplusplus
}
#endif
#endif
#endif
EOF
    cat mingw_shim.h src/common.h > src/common.h.tmp && mv src/common.h.tmp src/common.h

    # 修复 B: 清洗头文件引用
    sed -i 's/#include <sys\/resource.h>/\/\/ shimmed/g' src/util/sysutil.cpp
    sed -i 's/#include <sys\/sysinfo.h>/\/\/ shimmed/g' src/util/sysutil.cpp
    sed -i 's/#include <unistd.h>/\/\/ shimmed/g' src/util/sysutil.cpp
    sed -i 's/u_int32_t/uint32_t/g' src/util/sysutil.cpp

    # 修复 C: 强制在 CMakeLists.txt 中禁用 SIMD 优化 (Windows 稳定性关键)
    # 这会避开对对齐内存的硬性要求
    sed -i '2i set(ENABLE_RAXML_SIMD OFF CACHE BOOL "" FORCE)' CMakeLists.txt
    sed -i '3i set(ENABLE_PLLMOD_SIMD OFF CACHE BOOL "" FORCE)' CMakeLists.txt
    sed -i '4i set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fpermissive -Wno-error=int-conversion")' CMakeLists.txt

    # 修复 D: 递归修正子模块
    find . -name "CMakeLists.txt" -exec sed -i 's/cmake_minimum_required *(VERSION *[23]\.[0-9]/cmake_minimum_required(VERSION 3.10/g' {} +
    find libs -type f \( -name "*.h" -o -name "*.c" -o -name "*.cpp" -o -name "*.l" -o -name "*.y" \) -exec sed -i 's/\berrno\b/pll_errno/g' {} +
    find libs -name "parse_utree.y" -exec sed -i 's/extern int pll_utree_parse();/struct pll_unode_s; int pll_utree_parse(struct pll_unode_s * tree);/g' {} +
    find libs -name "parse_rtree.y" -exec sed -i 's/extern int pll_rtree_parse();/struct pll_rnode_s; int pll_rtree_parse(struct pll_rnode_s * tree);/g' {} +
fi

# 5. CMake 参数设置
# 强制开启 STATIC_BUILD 以实现单文件运行
CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DUSE_LIBPLL_CMAKE=ON -DUSE_GMP=ON -DUSE_PTHREADS=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DSTATIC_BUILD=ON"

case "${OS_TYPE}" in
    "windows")
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++"
        GENERATOR="MSYS Makefiles" ;;
    "macos")
        CMAKE_OPTS="${CMAKE_OPTS} -DSTATIC_BUILD=OFF"
        GENERATOR="Unix Makefiles"
        [ -d "/opt/homebrew" ] && BP="/opt/homebrew" || BP="/usr/local"
        export CMAKE_PREFIX_PATH="${BP}:${CMAKE_PREFIX_PATH}" ;;
    "linux")
        GENERATOR="Unix Makefiles" ;;
esac

# 6. ARM 指令集适配 (非 Windows 平台)
if [ "${ARCH_TYPE}" == "arm64" ] && [ "$OS_TYPE" != "windows" ]; then
    CMAKE_OPTS="${CMAKE_OPTS} -DENABLE_RAXML_SIMD=OFF -DENABLE_PLLMOD_SIMD=OFF"
    if [[ "$(uname -m)" != "aarch64" ]]; then
        CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++"
    fi
fi

# 7. 执行编译
rm -rf build_dir && mkdir build_dir && cd build_dir
cmake .. -G "$GENERATOR" ${CMAKE_OPTS}
make -j${MAKE_JOBS} || make

# 8. 产物收集
mkdir -p "${INSTALL_PREFIX}/bin"
# 查找主程序并统一命名
FOUND_BIN=$(find . -name "raxml-ng*${EXE_EXT}" -type f | grep -v "test" | head -n 1)
if [ -n "$FOUND_BIN" ]; then
    cp -f "$FOUND_BIN" "${INSTALL_PREFIX}/bin/raxml-ng${EXE_EXT}"
    log_info "Binary collected: raxml-ng${EXE_EXT}"
else
    log_err "raxml-ng binary not found!"
    exit 1
fi

log_info "Build successful!"
